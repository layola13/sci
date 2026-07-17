const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn setProcessEnvironmentVariable(allocator: std.mem.Allocator, name: []const u8, value: ?[]const u8) !void {
    if (builtin.os.tag == .windows) {
        const name_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name);
        defer allocator.free(name_w);
        const value_w = if (value) |bytes| try std.unicode.utf8ToUtf16LeAllocZ(allocator, bytes) else null;
        defer if (value_w) |bytes| allocator.free(bytes);

        if (std.os.windows.kernel32.SetEnvironmentVariableW(name_w.ptr, if (value_w) |bytes| bytes.ptr else null) != 0) return;
        if (value == null and std.os.windows.kernel32.GetLastError() == .ENVVAR_NOT_FOUND) return;
        return error.SetEnvironmentVariableFailed;
    }

    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);
    if (value) |bytes| {
        const value_z = try allocator.dupeZ(u8, bytes);
        defer allocator.free(value_z);
        if (setenv(name_z.ptr, value_z.ptr, 1) != 0) return error.SetEnvironmentVariableFailed;
    } else if (unsetenv(name_z.ptr) != 0) {
        return error.SetEnvironmentVariableFailed;
    }
}

fn parseJsonValue(allocator: std.mem.Allocator, text: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
}

fn jsonObjectGet(parsed: *const std.json.Parsed(std.json.Value), key: []const u8) !std.json.Value {
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    return root.get(key) orelse return error.TestUnexpectedResult;
}

fn jsonObjectGetValue(value: std.json.Value, key: []const u8) !std.json.Value {
    const object = switch (value) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    return object.get(key) orelse return error.TestUnexpectedResult;
}

fn jsonBoolValue(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.TestUnexpectedResult,
    };
}

fn jsonArrayCount(value: std.json.Value) !usize {
    return switch (value) {
        .array => |array| array.items.len,
        else => error.TestUnexpectedResult,
    };
}

fn jsonStringValue(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.TestUnexpectedResult,
    };
}

fn jsonPositiveU64Value(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |number| if (number > 0) @intCast(number) else error.TestUnexpectedResult,
        else => error.TestUnexpectedResult,
    };
}

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn writeBytes(dir: std.fs.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn bytesHashHex(bytes: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn writeCacheManifest(dir: std.fs.Dir, cache_dir: []const u8, kind: []const u8, key: []const u8, artifact: []const u8, output: []const u8) !void {
    const artifact_hash = bytesHashHex(artifact);
    const output_hash = bytesHashHex(output);
    const manifest = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"version\":2,\"kind\":\"{s}\",\"key\":\"{s}\",\"dynamic_dependencies\":[],\"artifact\":{{\"size\":{d},\"sha256\":\"{s}\"}},\"output\":{{\"size\":{d},\"sha256\":\"{s}\"}}}}\n",
        .{ kind, key, artifact.len, artifact_hash[0..], output.len, output_hash[0..] },
    );
    defer std.testing.allocator.free(manifest);
    const manifest_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/manifest.json", .{cache_dir});
    defer std.testing.allocator.free(manifest_path);
    try writeBytes(dir, manifest_path, manifest);
}

fn updateDirTimes(dir: std.fs.Dir, path: []const u8, atime: i128, mtime: i128) !void {
    var entry_dir = try dir.openDir(path, .{ .iterate = true });
    defer entry_dir.close();
    const entry_file = std.fs.File{ .handle = entry_dir.fd };
    try entry_file.updateTimes(atime, mtime);
}

fn freeStringMtimeMap(allocator: std.mem.Allocator, map: *std.StringHashMap(i128)) void {
    var iter = map.iterator();
    while (iter.next()) |entry| allocator.free(entry.key_ptr.*);
    map.deinit();
}

fn cachedFunctionObjectMtimes(allocator: std.mem.Allocator, dir: std.fs.Dir) !std.StringHashMap(i128) {
    var result = std.StringHashMap(i128).init(allocator);
    errdefer freeStringMtimeMap(allocator, &result);

    var cache_root = try dir.openDir(".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_root.close();
    var cache_iter = cache_root.iterate();
    while (try cache_iter.next()) |cache_entry| {
        if (cache_entry.kind != .directory) continue;
        var functions_dir = cache_root.openDir(cache_entry.name, .{ .iterate = true }) catch continue;
        defer functions_dir.close();
        var object_dir = functions_dir.openDir("functions", .{ .iterate = true }) catch continue;
        defer object_dir.close();

        var object_iter = object_dir.iterate();
        while (try object_iter.next()) |object_entry| {
            if (object_entry.kind != .file or !std.mem.endsWith(u8, object_entry.name, ".o")) continue;
            const key = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cache_entry.name, object_entry.name });
            errdefer allocator.free(key);
            const stat = try object_dir.statFile(object_entry.name);
            try result.put(key, stat.mtime);
        }
    }
    return result;
}

fn cachedFunctionManifestCount(dir: std.fs.Dir) !usize {
    var count: usize = 0;
    var cache_root = try dir.openDir(".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_root.close();
    var cache_iter = cache_root.iterate();
    while (try cache_iter.next()) |cache_entry| {
        if (cache_entry.kind != .directory) continue;
        var entry_dir = cache_root.openDir(cache_entry.name, .{ .iterate = true }) catch continue;
        defer entry_dir.close();
        const manifest = entry_dir.openFile("manifest.json", .{}) catch continue;
        manifest.close();
        count += 1;
    }
    return count;
}

fn isProjectCacheEntryName(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |byte| {
        switch (byte) {
            '0'...'9', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

fn singleCacheEntryName(allocator: std.mem.Allocator, dir: std.fs.Dir, rel_path: []const u8) ![]u8 {
    var cache_root = try dir.openDir(rel_path, .{ .iterate = true });
    defer cache_root.close();
    var cache_iter = cache_root.iterate();
    var found: ?[]u8 = null;
    errdefer if (found) |name| allocator.free(name);
    while (try cache_iter.next()) |entry| {
        if (entry.kind != .directory or !isProjectCacheEntryName(entry.name)) continue;
        if (found != null) return error.TestUnexpectedResult;
        found = try allocator.dupe(u8, entry.name);
    }
    return found orelse error.FileNotFound;
}

fn expectIncrementalManifestV2(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    expected_function_count: usize,
) ![]u8 {
    const cache_root_path = ".sa_cache/build-obj-incremental";
    const cache_key = try singleCacheEntryName(allocator, dir, cache_root_path);
    defer allocator.free(cache_key);

    const entry_path = try std.fs.path.join(allocator, &.{ cache_root_path, cache_key });
    defer allocator.free(entry_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ entry_path, "manifest.json" });
    defer allocator.free(manifest_path);
    const manifest_bytes = try dir.readFileAlloc(allocator, manifest_path, 16 * 1024 * 1024);
    defer allocator.free(manifest_bytes);
    var parsed = try parseJsonValue(allocator, manifest_bytes);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u64, 2), try jsonPositiveU64Value(try jsonObjectGet(&parsed, "version")));
    try std.testing.expectEqualStrings("build-obj-incremental", try jsonStringValue(try jsonObjectGet(&parsed, "kind")));
    try std.testing.expectEqualStrings(cache_key, try jsonStringValue(try jsonObjectGet(&parsed, "key")));

    const functions = switch (try jsonObjectGet(&parsed, "functions")) {
        .array => |array| array.items,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(expected_function_count, functions.len);

    var entry_dir = try dir.openDir(entry_path, .{});
    defer entry_dir.close();
    var seen_keys = std.StringHashMap(void).init(allocator);
    defer seen_keys.deinit();
    var selected_object_path: ?[]u8 = null;
    errdefer if (selected_object_path) |path| allocator.free(path);

    for (functions) |function_value| {
        const function_key = try jsonStringValue(try jsonObjectGetValue(function_value, "key"));
        try std.testing.expect(isProjectCacheEntryName(function_key));
        const seen = try seen_keys.getOrPut(function_key);
        try std.testing.expect(!seen.found_existing);

        const relative_path = try jsonStringValue(try jsonObjectGetValue(function_value, "path"));
        try std.testing.expect(!std.fs.path.isAbsolute(relative_path));
        const expected_path = try std.fmt.allocPrint(allocator, "functions/{s}.o", .{function_key});
        defer allocator.free(expected_path);
        try std.testing.expectEqualStrings(expected_path, relative_path);

        const declared_size = try jsonPositiveU64Value(try jsonObjectGetValue(function_value, "size"));
        const declared_sha256 = try jsonStringValue(try jsonObjectGetValue(function_value, "sha256"));
        try std.testing.expect(isProjectCacheEntryName(declared_sha256));

        const stat = try entry_dir.statFile(relative_path);
        try std.testing.expect(stat.kind == .file);
        try std.testing.expect(stat.size > 0);
        try std.testing.expectEqual(declared_size, stat.size);
        const object_bytes = try entry_dir.readFileAlloc(allocator, relative_path, 64 * 1024 * 1024);
        defer allocator.free(object_bytes);
        try std.testing.expectEqual(declared_size, @as(u64, @intCast(object_bytes.len)));
        const actual_sha256 = bytesHashHex(object_bytes);
        try std.testing.expectEqualStrings(declared_sha256, actual_sha256[0..]);

        if (selected_object_path == null) {
            selected_object_path = try std.fs.path.join(allocator, &.{ entry_path, relative_path });
        }
    }

    return selected_object_path orelse error.TestUnexpectedResult;
}

fn expectNoIncrementalTempFiles(allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
    var cache_root = try dir.openDir(".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_root.close();
    var walker = try cache_root.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        try std.testing.expect(std.mem.indexOf(u8, entry.basename, ".tmp.") == null);
    }
}

fn cacheEntryCount(dir: std.fs.Dir, rel_path: []const u8) !usize {
    var cache_root = try dir.openDir(rel_path, .{ .iterate = true });
    defer cache_root.close();
    var cache_iter = cache_root.iterate();
    var count: usize = 0;
    while (try cache_iter.next()) |entry| {
        if (entry.kind == .directory and isProjectCacheEntryName(entry.name)) count += 1;
    }
    return count;
}

fn writeManifestForPackage(
    dir: std.fs.Dir,
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

fn writeProjectSum(dir: std.fs.Dir, project_root: []const u8) !void {
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, "sa.mod" });
    defer std.testing.allocator.free(manifest_path);
    const manifest_source = try dir.readFileAlloc(std.testing.allocator, manifest_path, 16 * 1024 * 1024);
    defer std.testing.allocator.free(manifest_source);
    var project_manifest = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, manifest_source, manifest_path);
    defer project_manifest.deinit(std.testing.allocator);
    const root_abs = try dir.realpathAlloc(std.testing.allocator, project_root);
    defer std.testing.allocator.free(root_abs);
    var update = try saasm.pkg.sum.updateProjectSum(std.testing.allocator, root_abs, project_manifest);
    defer update.deinit(std.testing.allocator);
}

fn expectNoTextLlvmArtifacts(dir: std.fs.Dir, out_name: []const u8) !void {
    const ll_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.ll", .{out_name});
    defer std.testing.allocator.free(ll_name);
    const sa_ll_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.ll", .{out_name});
    defer std.testing.allocator.free(sa_ll_name);

    try std.testing.expectError(error.FileNotFound, dir.openFile(ll_name, .{}));
    try std.testing.expectError(error.FileNotFound, dir.openFile(sa_ll_name, .{}));
}

fn extractLineValue(output: []const u8, prefix: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, output, prefix) orelse return error.NotFound;
    const value_start = start + prefix.len;
    const value_end = std.mem.indexOfScalarPos(u8, output, value_start, '\n') orelse output.len;
    return std.mem.trim(u8, output[value_start..value_end], " \t\r");
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

fn runCommandAnyExitWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const std.process.EnvMap) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
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

    const run_argv = [_][]const u8{ "sa", "run", path };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    if (run_code != 0 or stderr_buf.items.len != 0 or !std.mem.eql(u8, stdout_buf.items, expected_stdout)) {
        std.debug.print("demo run failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

fn assertBuildExeStdout(path: []const u8, expected_stdout: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const print_iface = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/io/print.sai");
    defer std.testing.allocator.free(print_iface);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    try tmp.dir.makePath("bin");

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
        .Exited => |code| {
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

fn assertBuildExeStdoutPureBc(path: []const u8, expected_stdout: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const print_iface = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/io/print.sai");
    defer std.testing.allocator.free(print_iface);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    try tmp.dir.makePath("bin");

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
        .Exited => |code| {
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(out_name, .{}));
    const bc_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{out_name});
    defer std.testing.allocator.free(bc_name);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(bc_name, .{}));
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

fn assertBuildExeLinkFailure(source_name: []const u8, source: []const u8, out_name: []const u8, expected_fragment: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, source_name, source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_name, "-o", out_name };
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
    try std.testing.expect(std.mem.startsWith(u8, stderr_buffer.items, "error[ExternalCompiler]: zig cc exited with code 1 while linking "));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "  command: zig cc "));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, expected_fragment));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "error: ChildProcessFailed") == null);
}

fn assertRunStdoutWithArg(path: []const u8, arg: []const u8, expected_stdout: []const u8) !void {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", path, arg };
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
        \\@main() -> i32!:
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

    try writeSource(tmp.dir, "sample.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "sample.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 7), run_code);

    const exe_path = "sample.out";
    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "sample.sa", "-o", exe_path, "-g" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe = try tmp.dir.openFile(exe_path, .{});
    const exe_bytes = try exe.readToEndAlloc(std.testing.allocator, 1 << 20);
    exe.close();
    defer std.testing.allocator.free(exe_bytes);
    try std.testing.expect(exe_bytes.len > 0);

    const artifact_path = "sample.out.sa.bc";
    const artifact = try tmp.dir.openFile(artifact_path, .{});
    const artifact_bytes = try artifact.readToEndAlloc(std.testing.allocator, 1 << 20);
    artifact.close();
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    try tmp.dir.deleteFile(exe_path);
    try tmp.dir.deleteFile(artifact_path);
    const cached_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), cached_exe_code);
    const cached_artifact = try tmp.dir.openFile(artifact_path, .{});
    cached_artifact.close();
    if (builtin.os.tag != .windows) {
        const cached_exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./sample.out"});
        defer std.testing.allocator.free(cached_exe_result.stdout);
        defer std.testing.allocator.free(cached_exe_result.stderr);
        switch (cached_exe_result.term) {
            .Exited => |code| try std.testing.expectEqual(@as(u8, 7), code),
            else => return error.TestUnexpectedResult,
        }
    }

    const obj_path = "sample.o";
    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "sample.sa", "--jobs", "auto", "-o", obj_path };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj = try tmp.dir.openFile(obj_path, .{});
    defer obj.close();
    const obj_bytes = try obj.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const wasm_path = "sample.wasm";
    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "sample.sa", "--jobs", "auto", "-o", wasm_path, "--target", "wasm32" };
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

test "cli build-obj incremental reuses local cache layout" {
    const source =
        \\@const VTABLE = vtable { helper = @helper, spare = @vtable_only }
        \\@helper(value: i32) -> i32:
        \\next = add value, 1
        \\!value
        \\return next
        \\
        \\@vtable_only(value: i32) -> i32:
        \\next = add value, 3
        \\!value
        \\return next
        \\
        \\@main() -> i32:
        \\value = call @helper(6)
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "incremental.sa", source);

    const build_argv = [_][]const u8{ "sa", "build-obj", "incremental.sa", "--incremental", "--no-incremental", "-o", "incremental.o" };
    const first_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), first_code);
    const second_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), second_code);

    var before_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &before_mtimes);
    try std.testing.expectEqual(@as(u32, 3), before_mtimes.count());

    const scheduling_argv = [_][]const u8{ "sa", "build-obj", "incremental.sa", "--incremental", "--no-incremental", "--jobs", "2", "-o", "incremental.o" };
    const scheduling_code = try saasm.cli.execute(std.testing.allocator, scheduling_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), scheduling_code);
    var scheduling_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &scheduling_mtimes);
    try std.testing.expectEqual(before_mtimes.count(), scheduling_mtimes.count());
    var scheduling_iter = before_mtimes.iterator();
    while (scheduling_iter.next()) |entry| {
        try std.testing.expectEqual(entry.value_ptr.*, scheduling_mtimes.get(entry.key_ptr.*) orelse return error.TestUnexpectedResult);
    }
    const scheduling_cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/build-obj-incremental");
    defer std.testing.allocator.free(scheduling_cache_key);

    const modified_source =
        \\@const VTABLE = vtable { helper = @helper, spare = @vtable_only }
        \\@helper(value: i32) -> i32:
        \\intermediate = add value, 1
        \\renamed = add intermediate, 1
        \\!value
        \\!intermediate
        \\return renamed
        \\
        \\@vtable_only(value: i32) -> i32:
        \\next = add value, 3
        \\!value
        \\return next
        \\
        \\@main() -> i32:
        \\value = call @helper(6)
        \\return value
    ;
    try writeSource(tmp.dir, "incremental.sa", modified_source);
    const modified_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), modified_code);

    var after_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &after_mtimes);
    try std.testing.expectEqual(@as(u32, 3), after_mtimes.count());

    var reused_count: usize = 0;
    var before_iter = before_mtimes.iterator();
    while (before_iter.next()) |entry| {
        if (after_mtimes.get(entry.key_ptr.*)) |mtime| {
            if (mtime == entry.value_ptr.*) reused_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), reused_count);

    const corrupt_object_path = try expectIncrementalManifestV2(std.testing.allocator, tmp.dir, 3);
    defer std.testing.allocator.free(corrupt_object_path);
    const pristine_object = try tmp.dir.readFileAlloc(std.testing.allocator, corrupt_object_path, 64 * 1024 * 1024);
    defer std.testing.allocator.free(pristine_object);
    try std.testing.expect(pristine_object.len > 0);
    const zeroed_object = try std.testing.allocator.alloc(u8, pristine_object.len);
    defer std.testing.allocator.free(zeroed_object);
    @memset(zeroed_object, 0);
    try std.testing.expect(!std.mem.eql(u8, pristine_object, zeroed_object));
    try writeBytes(tmp.dir, corrupt_object_path, zeroed_object);

    const repaired_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), repaired_code);
    const repaired_object_path = try expectIncrementalManifestV2(std.testing.allocator, tmp.dir, 3);
    defer std.testing.allocator.free(repaired_object_path);
    try std.testing.expectEqualStrings(corrupt_object_path, repaired_object_path);
    const repaired_object = try tmp.dir.readFileAlloc(std.testing.allocator, repaired_object_path, 64 * 1024 * 1024);
    defer std.testing.allocator.free(repaired_object);
    try std.testing.expectEqualSlices(u8, pristine_object, repaired_object);
    try expectNoIncrementalTempFiles(std.testing.allocator, tmp.dir);

    const obj_file = try tmp.dir.openFile("incremental.o", .{});
    defer obj_file.close();
    const obj_bytes = try obj_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const linked_name = if (builtin.os.tag == .windows) "incremental-linked.exe" else "incremental-linked.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "incremental.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("incremental object link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const linked_run_path = if (builtin.os.tag == .windows) ".\\incremental-linked.exe" else "./incremental-linked.out";
    const linked_result = try runCommandAnyExit(std.testing.allocator, &.{linked_run_path});
    defer std.testing.allocator.free(linked_result.stdout);
    defer std.testing.allocator.free(linked_result.stderr);
    switch (linked_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 8), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), linked_result.stdout.len);
    try std.testing.expectEqual(@as(usize, 0), linked_result.stderr.len);

    const bc_file = try tmp.dir.openFile("incremental.o.sa.bc", .{});
    defer bc_file.close();
    const bc_bytes = try bc_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(bc_bytes);
    try std.testing.expect(bc_bytes.len > 0);

    var cache_dir = try tmp.dir.openDir(".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_dir.close();
    var cache_iter = cache_dir.iterate();
    try std.testing.expect((try cache_iter.next()) != null);
    try std.testing.expectEqual(@as(usize, 1), try cachedFunctionManifestCount(tmp.dir));

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const help_argv = [_][]const u8{ "sa", "build-obj", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--incremental") != null);
}

test "cli incremental raw quoted strings are function local" {
    const source =
        \\@extern sa_test_observe_anon(*text: ptr, tag: i32) -> i32
        \\@const __sa_anon_str_1 = utf8:"BAD!"
        \\@ffi_wrapper left_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"left", 1)
        \\return result
        \\@ffi_wrapper right_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"right", 2)
        \\return result
        \\@ffi_wrapper spare_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"spare", 3)
        \\return result
    ;
    const modified_source =
        \\@extern sa_test_observe_anon(*text: ptr, tag: i32) -> i32
        \\@const __sa_anon_str_1 = utf8:"BAD!"
        \\@ffi_wrapper left_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"LEFT", 1)
        \\return result
        \\@ffi_wrapper right_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"right", 2)
        \\return result
        \\@ffi_wrapper spare_probe() -> i32:
        \\result = call @sa_test_observe_anon(*"spare", 3)
        \\return result
    ;
    const driver_source =
        \\#include <stdint.h>
        \\static int matches(const char *actual, const char *expected, int length) {
        \\    for (int i = 0; i < length; ++i) {
        \\        if (actual[i] != expected[i]) return 0;
        \\    }
        \\    return 1;
        \\}
        \\int32_t sa_test_observe_anon(const char *text, int32_t tag) {
        \\    if (tag == 1) return matches(text, "LEFT", 4) ? 0 : 1;
        \\    if (tag == 2) return matches(text, "right", 5) ? 0 : 2;
        \\    if (tag == 3) return matches(text, "spare", 5) ? 0 : 4;
        \\    return 8;
        \\}
        \\extern int32_t left_probe(void);
        \\extern int32_t right_probe(void);
        \\extern int32_t spare_probe(void);
        \\int main(void) {
        \\    return left_probe() | right_probe() | spare_probe();
        \\}
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "anon.sa", source);
    try writeSource(tmp.dir, "driver.c", driver_source);

    const incremental_argv = [_][]const u8{ "sa", "build-obj", "anon.sa", "--incremental", "--no-incremental", "-o", "anon-incremental.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, incremental_argv[0..]));
    var before_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &before_mtimes);
    try std.testing.expectEqual(@as(u32, 3), before_mtimes.count());

    try writeSource(tmp.dir, "anon.sa", modified_source);
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, incremental_argv[0..]));
    var after_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &after_mtimes);
    try std.testing.expectEqual(@as(u32, 3), after_mtimes.count());

    var reused_count: usize = 0;
    var before_iter = before_mtimes.iterator();
    while (before_iter.next()) |entry| {
        if (after_mtimes.get(entry.key_ptr.*)) |mtime| {
            if (mtime == entry.value_ptr.*) reused_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), reused_count);

    const plain_argv = [_][]const u8{ "sa", "build-obj", "anon.sa", "--no-incremental", "-o", "anon-plain.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, plain_argv[0..]));

    const incremental_exe = if (builtin.os.tag == .windows) "anon-incremental.exe" else "anon-incremental.out";
    const plain_exe = if (builtin.os.tag == .windows) "anon-plain.exe" else "anon-plain.out";
    for ([_]struct { object: []const u8, exe: []const u8 }{
        .{ .object = "anon-incremental.o", .exe = incremental_exe },
        .{ .object = "anon-plain.o", .exe = plain_exe },
    }) |artifact| {
        const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", artifact.object, "-o", artifact.exe });
        defer std.testing.allocator.free(link_result.stdout);
        defer std.testing.allocator.free(link_result.stderr);
        switch (link_result.term) {
            .Exited => |code| {
                if (code != 0) std.debug.print("anonymous-string object link failed for {s}:\nstdout:\n{s}\nstderr:\n{s}\n", .{ artifact.object, link_result.stdout, link_result.stderr });
                try std.testing.expectEqual(@as(u8, 0), code);
            },
            else => return error.TestUnexpectedResult,
        }

        const run_path = if (builtin.os.tag == .windows)
            try std.fmt.allocPrint(std.testing.allocator, ".\\{s}", .{artifact.exe})
        else
            try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{artifact.exe});
        defer std.testing.allocator.free(run_path);
        const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
        defer std.testing.allocator.free(run_result.stdout);
        defer std.testing.allocator.free(run_result.stderr);
        switch (run_result.term) {
            .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
            else => return error.TestUnexpectedResult,
        }
        try std.testing.expectEqual(@as(usize, 0), run_result.stdout.len);
        try std.testing.expectEqual(@as(usize, 0), run_result.stderr.len);
    }
}

test "cli incremental local register slots ignore unrelated global symbol ids" {
    const source =
        \\@prefix() -> i32:
        \\changed = add 1, 1
        \\return changed
        \\@ffi_wrapper stable_probe() -> i32:
        \\a = add 1, 1
        \\b = add a, 1
        \\!a
        \\return b
    ;
    const modified_source =
        \\@prefix() -> i32:
        \\renamed = add 1, 1
        \\return renamed
        \\@ffi_wrapper stable_probe() -> i32:
        \\a = add 1, 1
        \\b = add a, 1
        \\!a
        \\return b
    ;
    const driver_source =
        \\#include <stdint.h>
        \\extern int32_t stable_probe(void);
        \\int main(void) { return stable_probe() == 3 ? 0 : 1; }
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "slots.sa", source);
    try writeSource(tmp.dir, "driver.c", driver_source);

    const build_argv = [_][]const u8{ "sa", "build-obj", "slots.sa", "--incremental", "--no-incremental", "--dce", "no", "-o", "slots.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, build_argv[0..]));
    var before_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &before_mtimes);
    try std.testing.expectEqual(@as(u32, 2), before_mtimes.count());

    try writeSource(tmp.dir, "slots.sa", modified_source);
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, build_argv[0..]));
    var after_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &after_mtimes);
    try std.testing.expectEqual(@as(u32, 2), after_mtimes.count());

    var reused_count: usize = 0;
    var before_iter = before_mtimes.iterator();
    while (before_iter.next()) |entry| {
        if (after_mtimes.get(entry.key_ptr.*)) |mtime| {
            if (mtime == entry.value_ptr.*) reused_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), reused_count);

    const linked_name = if (builtin.os.tag == .windows) "slots.exe" else "slots.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", "slots.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("local-slot object link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const run_path = if (builtin.os.tag == .windows) ".\\slots.exe" else "./slots.out";
    const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli incremental owned call release reaches free" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const source =
        \\@extern sa_test_touch(&value: ptr) -> void
        \\@const MAKER_VTABLE = vtable { make = @make_owned }
        \\#def MakerVTable_make = +0
        \\@make_owned() -> ^ptr:
        \\value = alloc 8
        \\return value
        \\@ffi_wrapper release_probe() -> i32:
        \\owned = call @make_owned()
        \\call @sa_test_touch(&owned)
        \\!owned
        \\return 0
        \\@ffi_wrapper indirect_release_probe() -> i32:
        \\vtable = &MAKER_VTABLE
        \\function = load vtable+MakerVTable_make as ptr
        \\owned = call_indirect function()
        \\!function
        \\!vtable
        \\call @sa_test_touch(&owned)
        \\!owned
        \\return 0
    ;
    const driver_source =
        \\#include <stdint.h>
        \\static int free_count = 0;
        \\static volatile uintptr_t touched = 0;
        \\void sa_test_touch(void *ptr) { touched = (uintptr_t)ptr; }
        \\void __wrap_free(void *ptr) {
        \\    (void)ptr;
        \\    ++free_count;
        \\}
        \\extern int32_t release_probe(void);
        \\extern int32_t indirect_release_probe(void);
        \\int main(void) {
        \\    if (release_probe() != 0) return 1;
        \\    if (indirect_release_probe() != 0) return 2;
        \\    return free_count == 2 ? 0 : 3;
        \\}
    ;
    const borrow_source =
        \\@extern sa_test_touch(&value: ptr) -> void
        \\@const BORROW_VTABLE = vtable { borrow = @borrowed_view }
        \\#def BorrowVTable_borrow = +0
        \\@borrowed_view(&owner: ptr) -> &ptr:
        \\return owner
        \\@ffi_wrapper borrowed_release_probe() -> i32:
        \\owner = alloc 8
        \\call @sa_test_touch(&owner)
        \\vtable = &BORROW_VTABLE
        \\function = load vtable+BorrowVTable_borrow as ptr
        \\view = call_indirect function(&owner)
        \\!function
        \\!vtable
        \\!view
        \\!owner
        \\return 0
    ;
    const borrow_driver_source =
        \\#include <stdint.h>
        \\static int free_count = 0;
        \\static volatile uintptr_t touched = 0;
        \\void sa_test_touch(void *ptr) { touched = (uintptr_t)ptr; }
        \\void __wrap_free(void *ptr) {
        \\    (void)ptr;
        \\    ++free_count;
        \\}
        \\extern int32_t borrowed_release_probe(void);
        \\int main(void) {
        \\    if (borrowed_release_probe() != 0) return 1;
        \\    return free_count == 1 ? 0 : 2;
        \\}
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "release.sa", source);
    try writeSource(tmp.dir, "driver.c", driver_source);
    try writeSource(tmp.dir, "borrow.sa", borrow_source);
    try writeSource(tmp.dir, "borrow-driver.c", borrow_driver_source);

    const plain_argv = [_][]const u8{ "sa", "build-obj", "release.sa", "--no-incremental", "-o", "release-plain.o" };
    const incremental_argv = [_][]const u8{ "sa", "build-obj", "release.sa", "--incremental", "--no-incremental", "-o", "release-incremental.o" };
    const borrow_argv = [_][]const u8{ "sa", "build-obj", "borrow.sa", "--incremental", "--no-incremental", "-o", "borrow-incremental.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, plain_argv[0..]));
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, incremental_argv[0..]));
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, borrow_argv[0..]));

    for ([_]struct { object: []const u8, exe: []const u8 }{
        .{ .object = "release-plain.o", .exe = "release-plain.out" },
        .{ .object = "release-incremental.o", .exe = "release-incremental.out" },
    }) |artifact| {
        const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "cc", "driver.c", artifact.object, "-Wl,--wrap=free", "-o", artifact.exe });
        defer std.testing.allocator.free(link_result.stdout);
        defer std.testing.allocator.free(link_result.stderr);
        switch (link_result.term) {
            .Exited => |code| {
                if (code != 0) std.debug.print("owned-release object link failed for {s}:\nstdout:\n{s}\nstderr:\n{s}\n", .{ artifact.object, link_result.stdout, link_result.stderr });
                try std.testing.expectEqual(@as(u8, 0), code);
            },
            else => return error.TestUnexpectedResult,
        }

        const run_path = try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{artifact.exe});
        defer std.testing.allocator.free(run_path);
        const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
        defer std.testing.allocator.free(run_result.stdout);
        defer std.testing.allocator.free(run_result.stderr);
        switch (run_result.term) {
            .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
            else => return error.TestUnexpectedResult,
        }
    }

    const borrow_link_result = try runCommandAnyExit(std.testing.allocator, &.{ "cc", "borrow-driver.c", "borrow-incremental.o", "-Wl,--wrap=free", "-o", "borrow-incremental.out" });
    defer std.testing.allocator.free(borrow_link_result.stdout);
    defer std.testing.allocator.free(borrow_link_result.stderr);
    switch (borrow_link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("borrowed-release object link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ borrow_link_result.stdout, borrow_link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const borrow_run_result = try runCommandAnyExit(std.testing.allocator, &.{"./borrow-incremental.out"});
    defer std.testing.allocator.free(borrow_run_result.stdout);
    defer std.testing.allocator.free(borrow_run_result.stderr);
    switch (borrow_run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli build-obj incremental without main owns process globals" {
    const source =
        \\@ffi_wrapper probe() -> i32:
        \\L_ENTRY:
        \\argc = call @sys_argc()
        \\return argc
    ;
    const driver_source =
        \\#include <stdint.h>
        \\extern int32_t probe(void);
        \\int main(void) {
        \\    return probe() == 0 ? 0 : 1;
        \\}
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "library.sa", source);
    try writeSource(tmp.dir, "driver.c", driver_source);
    const build_argv = [_][]const u8{ "sa", "build-obj", "library.sa", "--incremental", "--no-incremental", "-o", "library.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, build_argv[0..]));

    const linked_name = if (builtin.os.tag == .windows) "library-linked.exe" else "library-linked.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", "library.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("incremental library link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const linked_run_path = if (builtin.os.tag == .windows) ".\\library-linked.exe" else "./library-linked.out";
    const run_result = try runCommandAnyExit(std.testing.allocator, &.{linked_run_path});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), run_result.stdout.len);
    try std.testing.expectEqual(@as(usize, 0), run_result.stderr.len);
}

test "cli incremental function shards preserve global indirect provenance indices" {
    const source =
        \\@const CALLBACK_VTABLE = vtable { call = @callback }
        \\#def CallbackVTable_call = +0
        \\@unrelated(value: i64) -> i64:
        \\return value
        \\
        \\@callback(value: i32) -> i32:
        \\next = add value, 5
        \\!value
        \\return next
        \\
        \\@main() -> i32:
        \\vtable = &CALLBACK_VTABLE
        \\function = load vtable+CallbackVTable_call as ptr
        \\value = call_indirect function(7)
        \\!function
        \\!vtable
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "indirect.sa", source);

    const plain_argv = [_][]const u8{ "sa", "build-obj", "indirect.sa", "--no-incremental", "-o", "indirect-plain.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, plain_argv[0..]));
    const incremental_argv = [_][]const u8{ "sa", "build-obj", "indirect.sa", "--incremental", "--no-incremental", "-o", "indirect-incremental.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, incremental_argv[0..]));

    const plain_exe = if (builtin.os.tag == .windows) "indirect-plain.exe" else "indirect-plain.out";
    const incremental_exe = if (builtin.os.tag == .windows) "indirect-incremental.exe" else "indirect-incremental.out";
    for ([_]struct { object: []const u8, exe: []const u8 }{
        .{ .object = "indirect-plain.o", .exe = plain_exe },
        .{ .object = "indirect-incremental.o", .exe = incremental_exe },
    }) |artifact| {
        const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", artifact.object, "-o", artifact.exe });
        defer std.testing.allocator.free(link_result.stdout);
        defer std.testing.allocator.free(link_result.stderr);
        switch (link_result.term) {
            .Exited => |code| {
                if (code != 0) std.debug.print("indirect object link failed for {s}:\nstdout:\n{s}\nstderr:\n{s}\n", .{ artifact.object, link_result.stdout, link_result.stderr });
                try std.testing.expectEqual(@as(u8, 0), code);
            },
            else => return error.TestUnexpectedResult,
        }

        const run_path = if (builtin.os.tag == .windows)
            try std.fmt.allocPrint(std.testing.allocator, ".\\{s}", .{artifact.exe})
        else
            try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{artifact.exe});
        defer std.testing.allocator.free(run_path);
        const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
        defer std.testing.allocator.free(run_result.stdout);
        defer std.testing.allocator.free(run_result.stderr);
        switch (run_result.term) {
            .Exited => |code| try std.testing.expectEqual(@as(u8, 12), code),
            else => return error.TestUnexpectedResult,
        }
    }
}

test "cli incremental objects isolate same-named private functions across modules" {
    const left_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 1
        \\!value
        \\return next
        \\
        \\@ffi_wrapper left_probe() -> i32:
        \\value = call @helper(10)
        \\return value
    ;
    const right_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 2
        \\!value
        \\return next
        \\
        \\@ffi_wrapper right_probe() -> i32:
        \\value = call @helper(10)
        \\return value
    ;
    const driver_source =
        \\#include <stdint.h>
        \\extern int32_t left_probe(void);
        \\extern int32_t right_probe(void);
        \\int main(void) {
        \\    return left_probe() == 11 && right_probe() == 12 ? 0 : 1;
        \\}
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "left.sa", left_source);
    try writeSource(tmp.dir, "right.sa", right_source);
    try writeSource(tmp.dir, "driver.c", driver_source);

    const left_argv = [_][]const u8{ "sa", "build-obj", "left.sa", "--incremental", "--no-incremental", "-o", "left.o" };
    const right_argv = [_][]const u8{ "sa", "build-obj", "right.sa", "--incremental", "--no-incremental", "-o", "right.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, left_argv[0..]));
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, right_argv[0..]));

    const linked_name = if (builtin.os.tag == .windows) "private-collision.exe" else "private-collision.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", "left.o", "right.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("private symbol collision link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const run_path = if (builtin.os.tag == .windows) ".\\private-collision.exe" else "./private-collision.out";
    const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli incremental internal namespace changes with same-path global context" {
    const old_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 1
        \\!value
        \\return next
        \\
        \\@ffi_wrapper old_probe() -> i32:
        \\value = call @helper(20)
        \\return value
    ;
    const new_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 2
        \\!value
        \\return next
        \\
        \\@ffi_wrapper new_probe() -> i32:
        \\value = call @helper(20)
        \\return value
    ;
    const driver_source =
        \\#include <stdint.h>
        \\extern int32_t old_probe(void);
        \\extern int32_t new_probe(void);
        \\int main(void) {
        \\    return old_probe() == 21 && new_probe() == 22 ? 0 : 1;
        \\}
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "versioned.sa", old_source);
    const old_argv = [_][]const u8{ "sa", "build-obj", "versioned.sa", "--incremental", "--no-incremental", "-o", "old.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, old_argv[0..]));

    try writeSource(tmp.dir, "versioned.sa", new_source);
    const new_argv = [_][]const u8{ "sa", "build-obj", "versioned.sa", "--incremental", "--no-incremental", "-o", "new.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, new_argv[0..]));
    try writeSource(tmp.dir, "driver.c", driver_source);

    const linked_name = if (builtin.os.tag == .windows) "versioned-context.exe" else "versioned-context.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", "old.o", "new.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("same-path versioned object link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const run_path = if (builtin.os.tag == .windows) ".\\versioned-context.exe" else "./versioned-context.out";
    const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli incremental ELF output localizes same-path body-only private revisions" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const old_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 1
        \\!value
        \\return next
    ;
    const new_source =
        \\@helper(value: i32) -> i32:
        \\next = add value, 2
        \\!value
        \\return next
    ;
    const driver_source =
        \\int main(void) { return 0; }
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "private.sa", old_source);
    const old_argv = [_][]const u8{ "sa", "build-obj", "private.sa", "--incremental", "--no-incremental", "-o", "old.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, old_argv[0..]));

    try writeSource(tmp.dir, "private.sa", new_source);
    const new_argv = [_][]const u8{ "sa", "build-obj", "private.sa", "--incremental", "--no-incremental", "-o", "new.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, new_argv[0..]));
    try writeSource(tmp.dir, "driver.c", driver_source);

    for ([_][]const u8{ "old.o", "new.o" }) |object_path| {
        const global_symbols = try runCommand(std.testing.allocator, &.{ "nm", "-g", "--defined-only", object_path });
        defer std.testing.allocator.free(global_symbols);
        try std.testing.expect(std.mem.indexOf(u8, global_symbols, "__sa_internal_") == null);
    }

    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "driver.c", "old.o", "new.o", "-o", "body-only.out" });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("body-only private revision link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const run_result = try runCommandAnyExit(std.testing.allocator, &.{"./body-only.out"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli incremental full DCE prunes dead first task and assigns process globals owner" {
    const source =
        \\@dead(value: i32) -> i32:
        \\next = add value, 99
        \\!value
        \\return next
        \\
        \\@main() -> i32:
        \\return 9
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "dce.sa", source);

    const incremental_argv = [_][]const u8{ "sa", "build-obj", "dce.sa", "--incremental", "--no-incremental", "--dce", "full", "-o", "dce-incremental.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, incremental_argv[0..]));
    const manifest_object = try expectIncrementalManifestV2(std.testing.allocator, tmp.dir, 1);
    defer std.testing.allocator.free(manifest_object);

    const plain_argv = [_][]const u8{ "sa", "build-obj", "dce.sa", "--no-incremental", "--dce", "full", "-o", "dce-plain.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, plain_argv[0..]));

    if (builtin.os.tag == .linux) {
        const incremental_nm = try runCommand(std.testing.allocator, &.{ "nm", "--defined-only", "dce-incremental.o" });
        defer std.testing.allocator.free(incremental_nm);
        const plain_nm = try runCommand(std.testing.allocator, &.{ "nm", "--defined-only", "dce-plain.o" });
        defer std.testing.allocator.free(plain_nm);
        try std.testing.expect(std.mem.indexOf(u8, incremental_nm, "_dead") == null);
        try std.testing.expect(std.mem.indexOf(u8, plain_nm, " dead") == null);
        try std.testing.expect(std.mem.indexOf(u8, incremental_nm, " saasm_main") != null);
    }

    const linked_name = if (builtin.os.tag == .windows) "dce-incremental.exe" else "dce-incremental.out";
    const link_result = try runCommandAnyExit(std.testing.allocator, &.{ "zig", "cc", "dce-incremental.o", "-o", linked_name });
    defer std.testing.allocator.free(link_result.stdout);
    defer std.testing.allocator.free(link_result.stderr);
    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("incremental DCE object link failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ link_result.stdout, link_result.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const run_path = if (builtin.os.tag == .windows) ".\\dce-incremental.exe" else "./dce-incremental.out";
    const run_result = try runCommandAnyExit(std.testing.allocator, &.{run_path});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 9), code),
        else => return error.TestUnexpectedResult,
    }
}

test "cli build project cache is default and can be disabled" {
    const source =
        \\@main() -> i32:
        \\return 9
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "cached.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const build_argv = [_][]const u8{ "sa", "build-exe", "cached.sa", "-o", "cached.out", "--json", "--profile" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_metrics = try jsonObjectGet(&first_json, "metrics");
    const first_cache = try jsonObjectGetValue(first_metrics, "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    try tmp.dir.deleteFile("cached.out");
    try tmp.dir.deleteFile("cached.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    var second_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer second_json.deinit();
    const second_metrics = try jsonObjectGet(&second_json, "metrics");
    const second_cache = try jsonObjectGetValue(second_metrics, "cache");
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(second_cache, "reason")));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const cache_status_argv = [_][]const u8{ "sa", "cache", "status", "--kind", "build-exe", "--json" };
    const cache_status_code = try saasm.cli.executeWithWriters(std.testing.allocator, cache_status_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), cache_status_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_hit_ns\":"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "\"last_hit_ns\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_ns\":"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "\"last_store_ns\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_result\":\"published\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_writer_pid\":"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "\"last_store_writer_pid\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_event_count\":"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "\"last_store_event_count\":null") == null);

    const cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/build-exe");
    defer std.testing.allocator.free(cache_key);
    const cached_output_path = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/build-exe/{s}/output.bin", .{cache_key});
    defer std.testing.allocator.free(cached_output_path);
    const cached_manifest_path = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/build-exe/{s}/manifest.json", .{cache_key});
    defer std.testing.allocator.free(cached_manifest_path);

    try writeBytes(tmp.dir, cached_output_path, "tampered output");
    try tmp.dir.deleteFile("cached.out");
    try tmp.dir.deleteFile("cached.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const corrupt_artifact_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), corrupt_artifact_code);
    var corrupt_artifact_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer corrupt_artifact_json.deinit();
    const corrupt_artifact_cache = try jsonObjectGetValue(try jsonObjectGet(&corrupt_artifact_json, "metrics"), "cache");
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(corrupt_artifact_cache, "hit")));
    try std.testing.expectEqualStrings("artifact_corrupt", try jsonStringValue(try jsonObjectGetValue(corrupt_artifact_cache, "reason")));

    try writeBytes(tmp.dir, cached_manifest_path, "{\"version\":1,\"kind\":\"build-exe\",\"key\":\"bad\"}\n");
    try tmp.dir.deleteFile("cached.out");
    try tmp.dir.deleteFile("cached.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const invalid_manifest_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), invalid_manifest_code);
    var invalid_manifest_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer invalid_manifest_json.deinit();
    const invalid_manifest_cache = try jsonObjectGetValue(try jsonObjectGet(&invalid_manifest_json, "metrics"), "cache");
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(invalid_manifest_cache, "hit")));
    try std.testing.expectEqualStrings("manifest_invalid", try jsonStringValue(try jsonObjectGetValue(invalid_manifest_cache, "reason")));

    stderr_buf.clearRetainingCapacity();
    const no_cache_argv = [_][]const u8{ "sa", "build-exe", "cached.sa", "-o", "cached_no_cache.out", "--json", "--profile", "--no-incremental" };
    const no_cache_code = try saasm.cli.executeWithWriters(std.testing.allocator, no_cache_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), no_cache_code);
    var no_cache_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer no_cache_json.deinit();
    const no_cache_metrics = try jsonObjectGet(&no_cache_json, "metrics");
    const no_cache = try jsonObjectGetValue(no_cache_metrics, "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(no_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(no_cache, "hit")));
    try std.testing.expectEqualStrings("disabled", try jsonStringValue(try jsonObjectGetValue(no_cache, "reason")));

    try writeSource(tmp.dir, "lock_owner_failed.sa", source);
    try tmp.dir.deleteTree(".sa_cache/build-exe/.locks");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/.locks", "not a lock dir");
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const lock_owner_failed_argv = [_][]const u8{ "sa", "build-exe", "lock_owner_failed.sa", "-o", "lock_owner_failed.out", "--json", "--profile" };
    const lock_owner_failed_code = try saasm.cli.executeWithWriters(std.testing.allocator, lock_owner_failed_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), lock_owner_failed_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var lock_owner_failed_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer lock_owner_failed_json.deinit();
    const lock_owner_failed_cache = try jsonObjectGetValue(try jsonObjectGet(&lock_owner_failed_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(lock_owner_failed_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(lock_owner_failed_cache, "hit")));
    try std.testing.expectEqualStrings("lock_owner_failed", try jsonStringValue(try jsonObjectGetValue(lock_owner_failed_cache, "reason")));
    try tmp.dir.deleteFile(".sa_cache/build-exe/.locks");

    var cgu_source = std.ArrayList(u8).init(std.testing.allocator);
    defer cgu_source.deinit();
    try cgu_source.appendSlice(
        \\@main() -> i32:
        \\return 0
        \\
    );
    for (0..100) |idx| {
        try cgu_source.writer().print(
            \\@helper_{d}() -> i32:
            \\return {d}
            \\
        , .{ idx, idx });
    }
    try writeBytes(tmp.dir, "cgu_bypass.sa", cgu_source.items);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const cgu_bypass_argv = [_][]const u8{ "sa", "build-exe", "cgu_bypass.sa", "-o", "cgu_bypass.out", "--json", "--jobs", "2" };
    const cgu_bypass_code = try saasm.cli.executeWithWriters(std.testing.allocator, cgu_bypass_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), cgu_bypass_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var cgu_bypass_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer cgu_bypass_json.deinit();
    const cgu_bypass_cache = try jsonObjectGetValue(try jsonObjectGet(&cgu_bypass_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(cgu_bypass_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(cgu_bypass_cache, "hit")));
    try std.testing.expectEqualStrings("bypassed_untrusted", try jsonStringValue(try jsonObjectGetValue(cgu_bypass_cache, "reason")));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const help_argv = [_][]const u8{ "sa", "build-exe", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--no-incremental") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--mem-report") != null);
}

test "project cache manifest revalidates INCLUDE_STR dependencies" {
    const source =
        \\EXPAND INCLUDE_STR! "payload.txt"
        \\@main() -> i32:
        \\return 9
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "dynamic_include.sa", source);
    try writeBytes(tmp.dir, "payload.txt", "first payload");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const build_argv = [_][]const u8{ "sa", "build-exe", "dynamic_include.sa", "-o", "dynamic_include.out", "--json", "--profile", "--jobs", "1" };

    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_cache = try jsonObjectGetValue(try jsonObjectGet(&first_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    stderr_buf.clearRetainingCapacity();
    const warm_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), warm_code);
    var warm_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer warm_json.deinit();
    const warm_cache = try jsonObjectGetValue(try jsonObjectGet(&warm_json, "metrics"), "cache");
    try std.testing.expect(try jsonBoolValue(try jsonObjectGetValue(warm_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(warm_cache, "reason")));

    try writeBytes(tmp.dir, "payload.txt", "second payload");
    stderr_buf.clearRetainingCapacity();
    const changed_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), changed_code);
    var changed_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer changed_json.deinit();
    const changed_cache = try jsonObjectGetValue(try jsonObjectGet(&changed_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(changed_cache, "hit")));
    try std.testing.expectEqualStrings("dependency_changed", try jsonStringValue(try jsonObjectGetValue(changed_cache, "reason")));

    const cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/build-exe");
    defer std.testing.allocator.free(cache_key);
    const manifest_path = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/build-exe/{s}/manifest.json", .{cache_key});
    defer std.testing.allocator.free(manifest_path);
    const manifest_bytes = try tmp.dir.readFileAlloc(std.testing.allocator, manifest_path, 64 * 1024);
    defer std.testing.allocator.free(manifest_bytes);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, "dynamic_dependencies") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, "payload.txt") != null);
}

test "project cache manifest revalidates nested relative INCLUDE dependencies" {
    const source =
        \\EXPAND INCLUDE! "nested/fragment.sa"
        \\@main() -> i32:
        \\return nested_value
    ;
    const fragment =
        \\EXPAND INCLUDE_STR! "payload.txt"
        \\#def nested_value = 9
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("nested");
    try writeSource(tmp.dir, "main.sa", source);
    try writeSource(tmp.dir, "nested/fragment.sa", fragment);
    try writeBytes(tmp.dir, "nested/payload.txt", "first nested payload");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const build_argv = [_][]const u8{ "sa", "build-exe", "main.sa", "-o", "nested_include.out", "--json", "--profile", "--jobs", "1" };

    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_cache = try jsonObjectGetValue(try jsonObjectGet(&first_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    try tmp.dir.deleteFile("nested_include.out");
    try tmp.dir.deleteFile("nested_include.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const warm_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), warm_code);
    var warm_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer warm_json.deinit();
    const warm_cache = try jsonObjectGetValue(try jsonObjectGet(&warm_json, "metrics"), "cache");
    try std.testing.expect(try jsonBoolValue(try jsonObjectGetValue(warm_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(warm_cache, "reason")));

    try writeBytes(tmp.dir, "nested/payload.txt", "second nested payload");
    try tmp.dir.deleteFile("nested_include.out");
    try tmp.dir.deleteFile("nested_include.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const changed_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), changed_code);
    var changed_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer changed_json.deinit();
    const changed_cache = try jsonObjectGetValue(try jsonObjectGet(&changed_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(changed_cache, "hit")));
    try std.testing.expectEqualStrings("dependency_changed", try jsonStringValue(try jsonObjectGetValue(changed_cache, "reason")));

    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/build-exe"));
    const cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/build-exe");
    defer std.testing.allocator.free(cache_key);
    const manifest_path = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/build-exe/{s}/manifest.json", .{cache_key});
    defer std.testing.allocator.free(manifest_path);
    const manifest_bytes = try tmp.dir.readFileAlloc(std.testing.allocator, manifest_path, 64 * 1024);
    defer std.testing.allocator.free(manifest_bytes);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, "dynamic_dependencies") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, "fragment.sa") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, "payload.txt") != null);
}

test "project cache manifest revalidates OPTION_ENV absent to present" {
    const env_name = "SA_PROJECT_CACHE_OPTION_ENV_9E72D31B";
    const env_value = "cache-sensitive-secret-4c719a";
    const source =
        \\#def Slice_SIZE = 16
        \\#def Slice_ptr = +0
        \\#def Slice_len = +8
        \\#def Option_SIZE = 16
        \\#def Option_tag = +0
        \\#def Option_value = +8
        \\#def Option_NONE = 0
        \\#def Option_SOME = 1
        \\@main() -> i32:
        \\L_ENTRY:
        \\    option = alloc Option_SIZE
        \\    EXPAND OPTION_ENV! option, "SA_PROJECT_CACHE_OPTION_ENV_9E72D31B"
        \\    !option
        \\    return 9
    ;

    const original_env = std.process.getEnvVarOwned(std.testing.allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (original_env) |bytes| std.testing.allocator.free(bytes);
    try setProcessEnvironmentVariable(std.testing.allocator, env_name, null);
    defer setProcessEnvironmentVariable(std.testing.allocator, env_name, original_env) catch {};

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "dynamic_env.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const build_argv = [_][]const u8{ "sa", "build-exe", "dynamic_env.sa", "-o", "dynamic_env.out", "--json", "--profile", "--jobs", "1" };

    const absent_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), absent_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var absent_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer absent_json.deinit();
    const absent_cache = try jsonObjectGetValue(try jsonObjectGet(&absent_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(absent_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(absent_cache, "reason")));

    try tmp.dir.deleteFile("dynamic_env.out");
    try tmp.dir.deleteFile("dynamic_env.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const absent_warm_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), absent_warm_code);
    var absent_warm_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer absent_warm_json.deinit();
    const absent_warm_cache = try jsonObjectGetValue(try jsonObjectGet(&absent_warm_json, "metrics"), "cache");
    try std.testing.expect(try jsonBoolValue(try jsonObjectGetValue(absent_warm_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(absent_warm_cache, "reason")));

    try setProcessEnvironmentVariable(std.testing.allocator, env_name, env_value);
    try tmp.dir.deleteFile("dynamic_env.out");
    try tmp.dir.deleteFile("dynamic_env.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const present_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), present_code);
    var present_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer present_json.deinit();
    const present_cache = try jsonObjectGetValue(try jsonObjectGet(&present_json, "metrics"), "cache");
    try std.testing.expect(!try jsonBoolValue(try jsonObjectGetValue(present_cache, "hit")));
    try std.testing.expectEqualStrings("dependency_changed", try jsonStringValue(try jsonObjectGetValue(present_cache, "reason")));

    try tmp.dir.deleteFile("dynamic_env.out");
    try tmp.dir.deleteFile("dynamic_env.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const present_warm_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), present_warm_code);
    var present_warm_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer present_warm_json.deinit();
    const present_warm_cache = try jsonObjectGetValue(try jsonObjectGet(&present_warm_json, "metrics"), "cache");
    try std.testing.expect(try jsonBoolValue(try jsonObjectGetValue(present_warm_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(present_warm_cache, "reason")));

    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/build-exe"));
    const cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/build-exe");
    defer std.testing.allocator.free(cache_key);
    const manifest_path = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/build-exe/{s}/manifest.json", .{cache_key});
    defer std.testing.allocator.free(manifest_path);
    const manifest_bytes = try tmp.dir.readFileAlloc(std.testing.allocator, manifest_path, 64 * 1024);
    defer std.testing.allocator.free(manifest_bytes);
    try std.testing.expect(std.mem.indexOf(u8, manifest_bytes, env_value) == null);

    var manifest_json = try parseJsonValue(std.testing.allocator, manifest_bytes);
    defer manifest_json.deinit();
    const dependencies = switch (try jsonObjectGet(&manifest_json, "dynamic_dependencies")) {
        .array => |array| array.items,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 1), dependencies.len);
    const dependency = dependencies[0];
    try std.testing.expectEqualStrings("environment", try jsonStringValue(try jsonObjectGetValue(dependency, "kind")));
    try std.testing.expectEqualStrings(env_name, try jsonStringValue(try jsonObjectGetValue(dependency, "key")));
    try std.testing.expect(try jsonBoolValue(try jsonObjectGetValue(dependency, "present")));
    const expected_digest = bytesHashHex(env_value);
    try std.testing.expectEqualStrings(expected_digest[0..], try jsonStringValue(try jsonObjectGetValue(dependency, "sha256")));
}

test "project cache non-cacheable dynamic dependency reports bypassed" {
    const env_name = "SA_TEST_FORCE_NON_CACHEABLE_DYNAMIC_DEPENDENCY_51D4";
    const source =
        \\#def Slice_SIZE = 16
        \\#def Slice_ptr = +0
        \\#def Slice_len = +8
        \\#def Option_SIZE = 16
        \\#def Option_tag = +0
        \\#def Option_value = +8
        \\#def Option_NONE = 0
        \\#def Option_SOME = 1
        \\@main() -> i32:
        \\L_ENTRY:
        \\    option = alloc Option_SIZE
        \\    EXPAND OPTION_ENV! option, "SA_TEST_FORCE_NON_CACHEABLE_DYNAMIC_DEPENDENCY_51D4"
        \\    !option
        \\    return 9
    ;

    const original_env = std.process.getEnvVarOwned(std.testing.allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (original_env) |bytes| std.testing.allocator.free(bytes);
    try setProcessEnvironmentVariable(std.testing.allocator, env_name, null);
    defer setProcessEnvironmentVariable(std.testing.allocator, env_name, original_env) catch {};

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "dynamic_bypass.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const build_argv = [_][]const u8{ "sa", "build-exe", "dynamic_bypass.sa", "-o", "dynamic_bypass.out", "--json", "--profile", "--jobs", "1" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_cache = try jsonObjectGetValue(try jsonObjectGet(&first_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("bypassed_untrusted", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    const build_cache_entries = cacheEntryCount(tmp.dir, ".sa_cache/build-exe") catch |err| switch (err) {
        error.FileNotFound => 0,
        else => return err,
    };
    try std.testing.expectEqual(@as(usize, 0), build_cache_entries);

    try tmp.dir.deleteFile("dynamic_bypass.out");
    try tmp.dir.deleteFile("dynamic_bypass.out.sa.bc");
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    var second_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer second_json.deinit();
    const second_cache = try jsonObjectGetValue(try jsonObjectGet(&second_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(second_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));
    try std.testing.expectEqualStrings("bypassed_untrusted", try jsonStringValue(try jsonObjectGetValue(second_cache, "reason")));
}

test "cli cache clean removes invalid project cache entries" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const good_key = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const incomplete_key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const corrupt_manifest_key = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    try tmp.dir.makePath(".sa_cache/build-exe/" ++ good_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ good_key, "build-exe", good_key, "bc", "exe");
    try tmp.dir.makePath(".sa_cache/build-exe/" ++ incomplete_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ incomplete_key ++ "/artifact.sa.bc", "bc");
    try tmp.dir.makePath(".sa_cache/build-exe/" ++ corrupt_manifest_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key, "build-exe", corrupt_manifest_key, "bc", "wrong-output");
    try tmp.dir.makePath(".sa_cache/test/not-a-hex-key");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const clean_argv = [_][]const u8{ "sa", "cache", "clean", "--max-age-days", "0" };
    const clean_code = try saasm.cli.executeWithWriters(std.testing.allocator, clean_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), clean_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cache clean: scanned=4 removed=3 kept=1"));

    try tmp.dir.access(".sa_cache/build-exe/" ++ good_key ++ "/output.bin", .{});
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".sa_cache/build-exe/" ++ incomplete_key, .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".sa_cache/build-exe/" ++ corrupt_manifest_key, .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".sa_cache/test/not-a-hex-key", .{}));
    try tmp.dir.access(".sa_cache/.evictions/build-exe/" ++ incomplete_key, .{});
    try tmp.dir.access(".sa_cache/.evictions/build-exe/" ++ corrupt_manifest_key, .{});
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".sa_cache/.evictions/build-exe/" ++ good_key, .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(".sa_cache/.evictions/test/not-a-hex-key", .{}));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const evicted_why_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", incomplete_key, "--json" };
    const evicted_why_code = try saasm.cli.executeWithWriters(std.testing.allocator, evicted_why_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), evicted_why_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"reason\":\"evicted\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"manifest\":\"missing\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"bytes\":0"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const never_seen_key = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    const absent_why_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", never_seen_key, "--json" };
    const absent_why_code = try saasm.cli.executeWithWriters(std.testing.allocator, absent_why_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), absent_why_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"reason\":\"absent\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"manifest\":\"missing\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"bytes\":0"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const help_argv = [_][]const u8{ "sa", "cache", "clean", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--max-age-days") != null);
}

test "cli cache status and why explain project cache entries" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const good_key = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const incomplete_key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const corrupt_artifact_key = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    const invalid_manifest_key = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";

    try tmp.dir.makePath(".sa_cache/build-exe/" ++ good_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ good_key, "build-exe", good_key, "bc", "exe");

    try tmp.dir.makePath(".sa_cache/build-exe/" ++ incomplete_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ incomplete_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ incomplete_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ incomplete_key, "build-exe", incomplete_key, "bc", "exe");
    try tmp.dir.deleteFile(".sa_cache/build-exe/" ++ incomplete_key ++ "/output.bin");

    try tmp.dir.makePath(".sa_cache/build-exe/" ++ corrupt_artifact_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_artifact_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_artifact_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_artifact_key, "build-exe", corrupt_artifact_key, "bc", "wrong-output");

    try tmp.dir.makePath(".sa_cache/build-exe/" ++ invalid_manifest_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ invalid_manifest_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ invalid_manifest_key ++ "/output.bin", "exe");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ invalid_manifest_key ++ "/manifest.json", "{\"version\":1,\"kind\":\"build-exe\",\"key\":\"bad\"}\n");
    const old_mtime_ns = std.time.nanoTimestamp() - (@as(i128, 3) * 24 * 60 * 60 * std.time.ns_per_s);
    try updateDirTimes(tmp.dir, ".sa_cache/build-exe/" ++ good_key, old_mtime_ns, old_mtime_ns);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const status_argv = [_][]const u8{ "sa", "cache", "status", "--kind", "build-exe" };
    const status_code = try saasm.cli.executeWithWriters(std.testing.allocator, status_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), status_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cache status: root=.sa_cache"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cache status summary: entries=4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=bbbbbbbbbbbb reason=hit manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=aaaaaaaaaaaa reason=incomplete manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=cccccccccccc reason=artifact_corrupt manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=dddddddddddd reason=manifest_invalid manifest=invalid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 4, "last_hit_ns=null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 4, "last_store_ns=null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 4, "last_store_writer_pid=null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 4, "last_store_event_count=null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=output.file"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=output.size"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=manifest.version"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const expired_status_argv = [_][]const u8{ "sa", "cache", "status", "--kind", "build-exe", "--max-age-days=1" };
    const expired_status_code = try saasm.cli.executeWithWriters(std.testing.allocator, expired_status_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), expired_status_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=bbbbbbbbbbbb reason=expired manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "key=aaaaaaaaaaaa reason=incomplete manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "reason=expired manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=null"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const why_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", corrupt_artifact_key };
    const why_code = try saasm.cli.executeWithWriters(std.testing.allocator, why_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), why_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cache why: kind=build-exe key=cccccccccccc reason=artifact_corrupt manifest=valid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "first_difference=output.size"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const why_json_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", invalid_manifest_key, "--json" };
    const why_json_code = try saasm.cli.executeWithWriters(std.testing.allocator, why_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), why_json_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"reason\":\"manifest_invalid\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"key_prefix\":\"dddddddddddd\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_hit_ns\":null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_ns\":null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_writer_pid\":null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"last_store_event_count\":null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"first_difference\":\"manifest.version\""));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const why_expired_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", good_key, "--json", "--max-age-days", "1" };
    const why_expired_code = try saasm.cli.executeWithWriters(std.testing.allocator, why_expired_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), why_expired_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"reason\":\"expired\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"manifest\":\"valid\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"first_difference\":null"));

    var candidate_miss_key_buf = [_]u8{'b'} ** 64;
    candidate_miss_key_buf[12] = 'a';
    const candidate_miss_key = candidate_miss_key_buf[0..];
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const why_candidate_argv = [_][]const u8{ "sa", "cache", "why", "--kind", "build-exe", "--key", candidate_miss_key, "--json" };
    const why_candidate_code = try saasm.cli.executeWithWriters(std.testing.allocator, why_candidate_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), why_candidate_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"reason\":\"absent\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"key_prefix\":\"bbbbbbbbbbbb\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "\"first_difference\":\"key.digest\""));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, good_key) == null);

    stdout_buf.clearRetainingCapacity();
    const status_help_argv = [_][]const u8{ "sa", "cache", "status", "--help" };
    const status_help_code = try saasm.cli.executeWithWriters(std.testing.allocator, status_help_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), status_help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--max-age-days") != null);

    stdout_buf.clearRetainingCapacity();
    const why_help_argv = [_][]const u8{ "sa", "cache", "why", "--help" };
    const why_help_code = try saasm.cli.executeWithWriters(std.testing.allocator, why_help_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), why_help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--key") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--max-age-days") != null);
}

test "sa test compile-only reuses and repairs project test cache" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@test "cached test compile"():
        \\L_ENTRY:
        \\    return
    ;
    try writeSource(tmp.dir, "cached_test.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const test_argv = [_][]const u8{ "sa", "test", "cached_test.sa", "--compile-only", "--jobs", "1" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));

    const cache_key = try singleCacheEntryName(std.testing.allocator, tmp.dir, ".sa_cache/test");
    defer std.testing.allocator.free(cache_key);
    const cached_output = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/test/{s}/output.bin", .{cache_key});
    defer std.testing.allocator.free(cached_output);
    const cached_manifest = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/test/{s}/manifest.json", .{cache_key});
    defer std.testing.allocator.free(cached_manifest);
    const cached_metadata = try std.fmt.allocPrint(std.testing.allocator, ".sa_cache/test/{s}/test-metadata.json", .{cache_key});
    defer std.testing.allocator.free(cached_metadata);
    try tmp.dir.access(cached_manifest, .{});
    const metadata_bytes = try tmp.dir.readFileAlloc(std.testing.allocator, cached_metadata, 64 * 1024);
    defer std.testing.allocator.free(metadata_bytes);
    try std.testing.expect(std.mem.indexOf(u8, metadata_bytes, "cached test compile") != null);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const cached_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), cached_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));

    const tampered_metadata = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        metadata_bytes,
        "cached test compile",
        "tampered test cache",
    );
    defer std.testing.allocator.free(tampered_metadata);
    try writeBytes(tmp.dir, cached_metadata, tampered_metadata);
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const metadata_repair_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), metadata_repair_code);
    const repaired_metadata = try tmp.dir.readFileAlloc(std.testing.allocator, cached_metadata, 64 * 1024);
    defer std.testing.allocator.free(repaired_metadata);
    try std.testing.expect(std.mem.indexOf(u8, repaired_metadata, "cached test compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, repaired_metadata, "tampered test cache") == null);

    try tmp.dir.deleteFile(cached_output);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));
    try tmp.dir.access(cached_output, .{});

    try writeBytes(tmp.dir, cached_manifest, "{\"version\":1,\"kind\":\"test\",\"key\":\"bad\"}\n");
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const third_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), third_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));
    const repaired_manifest = try tmp.dir.readFileAlloc(std.testing.allocator, cached_manifest, 64 * 1024);
    defer std.testing.allocator.free(repaired_manifest);
    try std.testing.expect(std.mem.indexOf(u8, repaired_manifest, cache_key) != null);

    try writeSource(tmp.dir, "cached_test_json.sa",
        \\@test "cached test json metrics"():
        \\L_ENTRY:
        \\    return
    );

    const selected_json_argv = [_][]const u8{ "sa", "test", "cached_test_json.sa", "--compile-only", "--filter", "cached test json metrics", "--jobs", "1", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const selected_json_code = try saasm.cli.executeWithWriters(std.testing.allocator, selected_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), selected_json_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    var selected_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer selected_json.deinit();
    const selected_json_cache = try jsonObjectGetValue(try jsonObjectGet(&selected_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(selected_json_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(selected_json_cache, "hit")));
    try std.testing.expectEqualStrings("selection_changed", try jsonStringValue(try jsonObjectGetValue(selected_json_cache, "reason")));

    const test_json_argv = [_][]const u8{ "sa", "test", "cached_test_json.sa", "--compile-only", "--jobs", "1", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const json_first_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), json_first_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    var json_first = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer json_first.deinit();
    const json_first_cache = try jsonObjectGetValue(try jsonObjectGet(&json_first, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(json_first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(json_first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(json_first_cache, "reason")));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const json_second_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), json_second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    var json_second = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer json_second.deinit();
    const json_second_cache = try jsonObjectGetValue(try jsonObjectGet(&json_second, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(json_second_cache, "kind")));
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(json_second_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(json_second_cache, "reason")));

    try writeSource(tmp.dir, "cached_test_list_json.sa",
        \\@test "cached test list json metrics"():
        \\L_ENTRY:
        \\    return
    );

    const list_json_argv = [_][]const u8{ "sa", "test", "cached_test_list_json.sa", "--list", "--jobs", "1", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const list_json_code = try saasm.cli.executeWithWriters(std.testing.allocator, list_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), list_json_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cached test list json metrics"));
    var list_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer list_json.deinit();
    const list_json_cache = try jsonObjectGetValue(try jsonObjectGet(&list_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(list_json_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(list_json_cache, "hit")));
    try std.testing.expectEqualStrings("selection_changed", try jsonStringValue(try jsonObjectGetValue(list_json_cache, "reason")));

    const disabled_list_json_argv = [_][]const u8{ "sa", "test", "cached_test_list_json.sa", "--list", "--jobs", "1", "--no-incremental", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const disabled_list_json_code = try saasm.cli.executeWithWriters(std.testing.allocator, disabled_list_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), disabled_list_json_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cached test list json metrics"));
    var disabled_list_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer disabled_list_json.deinit();
    const disabled_list_json_cache = try jsonObjectGetValue(try jsonObjectGet(&disabled_list_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(disabled_list_json_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(disabled_list_json_cache, "hit")));
    try std.testing.expectEqualStrings("disabled", try jsonStringValue(try jsonObjectGetValue(disabled_list_json_cache, "reason")));

    const cached_list_json_argv = [_][]const u8{ "sa", "test", "cached_test_json.sa", "--list", "--jobs", "1", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const cached_list_json_code = try saasm.cli.executeWithWriters(std.testing.allocator, cached_list_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), cached_list_json_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cached test json metrics"));
    var cached_list_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer cached_list_json.deinit();
    const cached_list_json_cache = try jsonObjectGetValue(try jsonObjectGet(&cached_list_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(cached_list_json_cache, "kind")));
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(cached_list_json_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(cached_list_json_cache, "reason")));

    try writeSource(tmp.dir, "cached_test_run_json.sa",
        \\@test "cached ordinary test json metrics"():
        \\L_ENTRY:
        \\    return
    );

    const test_run_json_argv = [_][]const u8{ "sa", "test", "cached_test_run_json.sa", "--jobs", "1", "--json" };
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const run_json_first_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_run_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), run_json_first_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    var run_json_first = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer run_json_first.deinit();
    const run_json_first_cache = try jsonObjectGetValue(try jsonObjectGet(&run_json_first, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(run_json_first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(run_json_first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(run_json_first_cache, "reason")));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const run_json_second_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_run_json_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), run_json_second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    var run_json_second = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer run_json_second.deinit();
    const run_json_second_cache = try jsonObjectGetValue(try jsonObjectGet(&run_json_second, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(run_json_second_cache, "kind")));
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(run_json_second_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(run_json_second_cache, "reason")));
}

test "sa test plugin link inputs report bypassed project cache" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "cache_link_plugin.zig",
        \\const std = @import("std");
        \\
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
        \\};
        \\
        \\const Context = struct {
        \\    allocator: std.mem.Allocator,
        \\    host_version: ?[]const u8 = null,
        \\    log: ?*const fn (ctx: *const anyopaque, level: u8, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
        \\    log_ctx: ?*anyopaque = null,
        \\    json_mode: bool = false,
        \\};
        \\
        \\const HostStream = extern struct {
        \\    ctx: ?*anyopaque,
        \\    write_all: ?*const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32,
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
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "cache-link-plugin",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
        \\pub export fn sa_cache_plugin_probe() u32 {
        \\    return 0;
        \\}
    );
    try writeSource(tmp.dir, "plugin_cache_test.sa",
        \\@extern sa_cache_plugin_probe() -> u32
        \\
        \\@test "plugin cache bypass"():
        \\L_ENTRY:
        \\    status = call @sa_cache_plugin_probe()
        \\    ok = eq status, 0
        \\    !status
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return
        \\
        \\L_ERR:
        \\    !ok
        \\    panic(902)
    );

    const build_plugin = try runCommandAnyExit(std.testing.allocator, &.{
        "zig",
        "build-lib",
        "cache_link_plugin.zig",
        "-dynamic",
        "-O",
        "Debug",
        "-femit-bin=libcache_link_plugin.so",
    });
    defer std.testing.allocator.free(build_plugin.stdout);
    defer std.testing.allocator.free(build_plugin.stderr);
    switch (build_plugin.term) {
        .Exited => |code| {
            if (code != 0) std.debug.print("plugin cache build failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ build_plugin.stdout, build_plugin.stderr });
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }

    const env_name = "SA_PLUGINS_PATH";
    const saved_env = std.process.getEnvVarOwned(std.testing.allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer {
        if (saved_env) |value| {
            setProcessEnvironmentVariable(std.testing.allocator, env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            setProcessEnvironmentVariable(std.testing.allocator, env_name, null) catch {};
        }
    }
    try setProcessEnvironmentVariable(std.testing.allocator, env_name, ".");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const test_argv = [_][]const u8{ "sa", "test", "plugin_cache_test.sa", "--jobs", "1", "--json" };

    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    if (first_code != 0) std.debug.print("plugin cache test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buf.items, stderr_buf.items });
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_cache = try jsonObjectGetValue(try jsonObjectGet(&first_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("bypassed_untrusted", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    var second_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer second_json.deinit();
    const second_cache = try jsonObjectGetValue(try jsonObjectGet(&second_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(second_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));
    try std.testing.expectEqualStrings("bypassed_untrusted", try jsonStringValue(try jsonObjectGetValue(second_cache, "reason")));

    const test_cache_entries = cacheEntryCount(tmp.dir, ".sa_cache/test") catch |err| switch (err) {
        error.FileNotFound => 0,
        else => return err,
    };
    try std.testing.expectEqual(@as(usize, 0), test_cache_entries);
}

test "artifact cache hits revalidate the current package permission request before restore" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@main() -> i32:
        \\L_MAIN:
        \\    return 0
        \\
        \\@test "cached permission preflight"():
        \\L_TEST:
        \\    return
    ;
    const project_manifest =
        \\permission_set dev {
        \\  env []
        \\  read []
        \\  write []
        \\  net []
        \\  run []
        \\}
    ;
    try writeSource(tmp.dir, "scoped.sa", source);
    try writeSource(tmp.dir, "sa.mod", project_manifest);

    const CommandCase = struct {
        cache_dir: []const u8,
        warm_argv: []const []const u8,
        rejected_argv: []const []const u8,
        output_path: ?[]const u8,
        artifact_path: ?[]const u8,
    };
    const cases = [_]CommandCase{
        .{
            .cache_dir = ".sa_cache/build-exe",
            .warm_argv = &.{ "sa", "build-exe", "scoped.sa", "-o", "scoped.out", "--permission-set=dev", "--jobs", "1" },
            .rejected_argv = &.{ "sa", "build-exe", "scoped.sa", "-o", "scoped.out", "--permission-set=missing", "--jobs", "1" },
            .output_path = "scoped.out",
            .artifact_path = "scoped.out.sa.bc",
        },
        .{
            .cache_dir = ".sa_cache/build-obj",
            .warm_argv = &.{ "sa", "build-obj", "scoped.sa", "-o", "scoped.o", "--permission-set=dev", "--jobs", "1" },
            .rejected_argv = &.{ "sa", "build-obj", "scoped.sa", "-o", "scoped.o", "--permission-set=missing", "--jobs", "1" },
            .output_path = "scoped.o",
            .artifact_path = "scoped.o.sa.bc",
        },
        .{
            .cache_dir = ".sa_cache/build-wasm",
            .warm_argv = &.{ "sa", "build-wasm", "scoped.sa", "-o", "scoped.wasm", "--permission-set=dev", "--jobs", "1" },
            .rejected_argv = &.{ "sa", "build-wasm", "scoped.sa", "-o", "scoped.wasm", "--permission-set=missing", "--jobs", "1" },
            .output_path = "scoped.wasm",
            .artifact_path = "scoped.wasm.sa.bc",
        },
        .{
            .cache_dir = ".sa_cache/test",
            .warm_argv = &.{ "sa", "test", "scoped.sa", "--compile-only", "--permission-set=dev", "--jobs", "1" },
            .rejected_argv = &.{ "sa", "test", "scoped.sa", "--compile-only", "--permission-set=missing", "--jobs", "1" },
            .output_path = null,
            .artifact_path = null,
        },
    };

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    for (cases) |case| {
        stdout_buf.clearRetainingCapacity();
        stderr_buf.clearRetainingCapacity();
        const warm_code = try saasm.cli.executeWithWriters(
            std.testing.allocator,
            case.warm_argv,
            stdout_buf.writer(),
            stderr_buf.writer(),
        );
        try std.testing.expectEqual(@as(u8, 0), warm_code);
        try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, case.cache_dir));

        if (case.output_path) |path| try tmp.dir.deleteFile(path);
        if (case.artifact_path) |path| try tmp.dir.deleteFile(path);

        stdout_buf.clearRetainingCapacity();
        stderr_buf.clearRetainingCapacity();
        try std.testing.expectError(
            error.InvalidPermissionSet,
            saasm.cli.executeWithWriters(
                std.testing.allocator,
                case.rejected_argv,
                stdout_buf.writer(),
                stderr_buf.writer(),
            ),
        );
        try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
        try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
        try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, case.cache_dir));
        if (case.output_path) |path| {
            try std.testing.expectError(error.FileNotFound, tmp.dir.access(path, .{ .mode = .read_only }));
        }
        if (case.artifact_path) |path| {
            try std.testing.expectError(error.FileNotFound, tmp.dir.access(path, .{ .mode = .read_only }));
        }
    }
}

test "warm build artifact cannot bypass current package confirmation" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/sa_vendor/risky/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\L_MAIN:
        \\    return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/risky/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/sa_vendor/risky/pkg");
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "risky/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const argv = [_][]const u8{ "sa", "build-exe", "src/main.sa", "-o", "approved.out", "--jobs", "1", "--json" };

    var approval_input = std.io.fixedBufferStream("risky/pkg\n");
    const warm_code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        argv[0..],
        stdout_buf.writer(),
        stderr_buf.writer(),
        .{ .stdin_reader = approval_input.reader().any(), .stdin_is_tty = true },
    );
    try std.testing.expectEqual(@as(u8, 0), warm_code);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(std.fs.cwd(), ".sa_cache/build-exe"));
    try std.fs.cwd().deleteFile("approved.out");
    try std.fs.cwd().deleteFile("approved.out.sa.bc");

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    var rejected_input = std.io.fixedBufferStream("");
    const rejected_code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        argv[0..],
        stdout_buf.writer(),
        stderr_buf.writer(),
        .{ .stdin_reader = rejected_input.reader().any(), .stdin_is_tty = false },
    );
    try std.testing.expectEqual(@as(u8, 1), rejected_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "\"trap\":\"MissingTtyForConfirmation\""));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access("approved.out", .{ .mode = .read_only }));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access("approved.out.sa.bc", .{ .mode = .read_only }));
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(std.fs.cwd(), ".sa_cache/build-exe"));
}

test "cli build-exe with jobs 1 and auto produce bitcode artifacts" {
    const source =
        \\@helper(value: i32) -> i32:
        \\return value
        \\
        \\@main() -> i32!:
        \\value = call @helper(7)
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);

    try writeSource(tmp.dir, "jobs_ok.sa", source);
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "jobs_ok.sa" });
    defer std.testing.allocator.free(source_path);
    const serial_out_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "serial.out" });
    defer std.testing.allocator.free(serial_out_path);
    const auto_out_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "auto.out" });
    defer std.testing.allocator.free(auto_out_path);

    const serial_build_argv = [_][]const u8{ "sa", "build-exe", source_path, "--jobs", "1", "-o", serial_out_path };
    const serial_code = try saasm.cli.execute(std.testing.allocator, serial_build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), serial_code);

    const auto_build_argv = [_][]const u8{ "sa", "build-exe", source_path, "--jobs", "auto", "-o", auto_out_path };
    const auto_code = try saasm.cli.execute(std.testing.allocator, auto_build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), auto_code);

    const serial_artifact_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{serial_out_path});
    defer std.testing.allocator.free(serial_artifact_path);
    const auto_artifact_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{auto_out_path});
    defer std.testing.allocator.free(auto_artifact_path);
    const serial_artifact = try tmp.dir.openFile(serial_artifact_path, .{});
    defer serial_artifact.close();
    const serial_artifact_bytes = try serial_artifact.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(serial_artifact_bytes);

    const auto_artifact = try tmp.dir.openFile(auto_artifact_path, .{});
    defer auto_artifact.close();
    const auto_artifact_bytes = try auto_artifact.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(auto_artifact_bytes);

    try std.testing.expect(serial_artifact_bytes.len > 0);
    try std.testing.expect(auto_artifact_bytes.len > 0);
    try expectNoTextLlvmArtifacts(tmp.dir, "serial.out");
    try expectNoTextLlvmArtifacts(tmp.dir, "auto.out");
}

test "cli build-exe prunes unused imported functions before llvm emission" {
    const source =
        \\@import "sa_std/sort.sa"
        \\
        \\@main() -> i32:
        \\return 0
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "unused_sort_import.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "unused_sort_import.sa", "-o", "unused_sort_import.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const artifact_file = try tmp.dir.openFile("unused_sort_import.out.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);
}

test "cli run with jobs 2 keeps the earliest source-order trap" {
    const source =
        \\@first() -> i32:
        \\a = alloc 8
        \\b = alloc 8
        \\c = alloc 8
        \\d = alloc 8
        \\e = alloc 8
        \\f = alloc 8
        \\g = alloc 8
        \\h = alloc 8
        \\return first_missing
        \\
        \\@second() -> i32:
        \\return second_missing
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "parallel_trap.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "parallel_trap.sa", "--jobs", "2" };
    const code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "\"trap\":\"UnknownRegister\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "return first_missing"));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buf.items, "return second_missing") == null);
}

test "hello world demo prints through sa run" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "demos/rosetta/01_hello_world/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "extern_run.sa", source);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "extern_run.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 1), run_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "sa run unsupported extern: sa_missing_plugin"));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buf.items, "UnsupportedExtern") == null);
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

    const node_result = try runWasmWithNode(std.testing.allocator, "hello.wasm", &.{ "sa", "hello.wasm" });
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
    try writeSource(tmp.dir, "hello.sa", source);
    try writeSource(tmp.dir, "hello.rs", upstream_source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "hello.sa", "-o", "hello.out", "-g" };
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

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/98_build_pipeline/main.sa");
    defer std.testing.allocator.free(source_path);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "hello_compute.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./hello_compute.out"});
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

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "hello_compute.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const node_result = try runWasmWithNode(std.testing.allocator, "hello_compute.wasm", &.{ "sa", "hello_compute.wasm" });
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

test "trait vtable demo runs through sa run" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "demos/rosetta/07_trait_vtable/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings("77\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "callback registration demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/rosetta/253_contract_callback_registration/main.sa", "253\n");
}

test "pkg lib dynamic demo compiles via object archive and prints through native link" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
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

test "async await demo runs through sa run" {
    try assertRunStdout("demos/rosetta/09_async_await/main.sa", "2\n");
}

test "macro demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/macro_print.sa", "macro ok\n");
}

test "sa_core macros compile and print through imported standard library macros" {
    try assertBuildExeStdout("demos/support/macro_core.sa", "macro core ok\n");
}

test "time demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/time_probe.sa", "time ok\n");
}

test "time demo runs through sa run" {
    try assertRunStdout("demos/support/time_probe.sa", "time ok\n");
}

test "pthread vtable worker stores survive native join" {
    try assertBuildExeStdout("demos/support/pthread_vtable_store/main.sa", "ok\n");
}

test "mutex demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/mutex_probe.sa", "mutex ok\n");
}

test "mutex demo runs through sa run" {
    try assertRunStdout("demos/support/mutex_probe.sa", "mutex ok\n");
}

test "once demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/once_probe.sa", "once ok\n");
}

test "once demo runs through sa run" {
    try assertRunStdout("demos/support/once_probe.sa", "once ok\n");
}

test "mpsc demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

test "mpsc demo runs through sa run" {
    try assertRunStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

test "io demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/io_probe.sa", "alpha\n5\n");
}

test "hashmap demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/hashmap_probe.sa", "alpha\nbravo\nmap ok\n");
}

test "hashset demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/hashset_probe.sa", "set ok\n");
}

test "hashset demo runs through sa run" {
    try assertRunStdout("demos/support/hashset_probe.sa", "set ok\n");
}

test "sort demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/sort_probe.sa", "sort ok\n");
}

test "use after move demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/use_after_move.sa", "use_after_move.out", "UseAfterMove", 1009, "moved value is no longer usable");
}

test "return after move demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/return_after_move.sa", "return_after_move.out", "UseAfterMove", 1009, "moved value is no longer usable");
}

test "borrow conflict demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/borrow_conflict.sa", "borrow_conflict.out", "BorrowConflict", 1008, "borrow rules reject this access");
}

test "read write conflict demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/read_write_conflict.sa", "read_write_conflict.out", "ReadWriteConflict", 1011, "cannot write through a shared borrow");
}

test "illegal unsafe context demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/illegal_unsafe_context.sa", "illegal_unsafe_context.out", "IllegalUnsafeContext", 1019, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper");
}

test "stack escape demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/stack_escape.sa", "stack_escape.out", "StackEscape", 1025, "stack allocation cannot be moved out of its function");
}

test "const mutation demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/const_mutation.sa", "const_mutation.out", "ConstMutation", 1023, "immutable registers cannot be released");
}

test "early return leak demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/early_return_leak.sa", "early_return_leak.out", "EarlyReturnLeak", 1026, "early return would leak live registers");
}

test "macro recursion demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/macro_recursion.sa", "macro_recursion.out", "MacroRecursionLimit", 1005, "macro recursion limit exceeded");
}

test "forbidden syntax demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_syntax.sa", "forbidden_syntax.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden if demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_if.sa", "forbidden_if.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden while demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_while.sa", "forbidden_while.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden for demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_for.sa", "forbidden_for.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden brace demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_brace.sa", "forbidden_brace.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden property chain demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_property_chain.sa", "forbidden_property_chain.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "memory leak after borrow demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/memory_leak_after_borrow.sa", "memory_leak_after_borrow.out", "MemoryLeak", 1012, "live registers remain at function exit");
}

test "memory leak partial release demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/memory_leak_partial_release.sa", "memory_leak_partial_release.out", "MemoryLeak", 1012, "live registers remain at function exit");
}

test "atomic ordering mismatch demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/atomic_ordering_mismatch.sa", "atomic_ordering_mismatch.out", "AtomicOrderingMismatch", 1029, "same-address RMW ordering combination is not allowed");
}

test "invalid atomic ordering demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/invalid_atomic_ordering.sa", "invalid_atomic_ordering.out", "InvalidAtomicOrdering", 1028, "invalid atomic ordering");
}

test "unknown register return demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/unknown_register_return.sa", "unknown_register_return.out", "UnknownRegister", 1007, "register is not declared in the current scope");
}

test "capability mismatch demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/capability_mismatch.sa", "capability_mismatch.out", "CapabilityMismatch", 1013, "call-site capability prefix does not match the callee contract");
}

test "package and module roadmap demos are rejected with structured trap output" {
    try assertBuildExeTrap("demos/rosetta/205_pkg_cyclic_dependency_reject/main.sa", "205_pkg_cyclic_dependency_reject.out", "ForbiddenSyntax", 1001, "import cycle detected during flattening");
    try assertBuildExeTrap("demos/rosetta/207_pkg_multiple_versions_conflict/main.sa", "207_pkg_multiple_versions_conflict.out", "DuplicateDef", 1002, "duplicate definition detected during flattening");
    try assertBuildExeTrap("demos/rosetta/226_mod_cyclic_import_detect/main.sa", "226_mod_cyclic_import_detect.out", "ForbiddenSyntax", 1001, "import cycle detected during flattening");
    try assertBuildExeTrap("demos/rosetta/227_mod_shadowing_prevention/main.sa", "227_mod_shadowing_prevention.out", "DuplicateDef", 1002, "duplicate definition detected during flattening");
    try assertBuildExeTrap("demos/rosetta/243_contract_sig_mismatch_link/main.sa", "243_contract_sig_mismatch_link.out", "CapabilityMismatch", 1013, "call-site capability prefix does not match the callee contract");
}

test "struct demo runs through sa run" {
    try assertRunStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
}

test "sys runtime demo prints and round-trips file contents" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/sys_runtime_probe.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdoutWithArg(source_path, "marker", "ok\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "sys_runtime_probe.out" };
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

    const file = try tmp.dir.openFile("sys_io.txt", .{});
    defer file.close();
    const contents = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("saasm", contents);

    try tmp.dir.deleteFile("sys_io.txt");

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "sys_runtime_probe.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_artifact = try tmp.dir.openFile("sys_runtime_probe.wasm.sa.bc", .{});
    defer wasm_artifact.close();
    const wasm_artifact_bytes = try wasm_artifact.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_artifact_bytes);
    try std.testing.expect(wasm_artifact_bytes.len > 0);
    try expectNoTextLlvmArtifacts(tmp.dir, "sys_runtime_probe.wasm");

    const wasm_file = try tmp.dir.openFile("sys_runtime_probe.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

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

    const wasm_result = try runWasmWithNode(std.testing.allocator, "sys_runtime_probe.wasm", &.{ "sa", "sys_runtime_probe.wasm", "marker" });
    defer std.testing.allocator.free(wasm_result.stdout);
    defer std.testing.allocator.free(wasm_result.stderr);
    switch (wasm_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, wasm_result.stdout, "ok\n") or wasm_result.stderr.len != 0) {
                std.debug.print("wasm sys runtime demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ wasm_result.stdout, wasm_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", wasm_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), wasm_result.stderr.len);

    const wasm_written_file = try tmp.dir.openFile("sys_io.txt", .{});
    defer wasm_written_file.close();
    const wasm_written = try wasm_written_file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(wasm_written);
    try std.testing.expectEqualStrings("saasm", wasm_written);
}

test "ffi airlock demo preserves pointer values through assume_* in sa run" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/airlock_probe.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdout(source_path, "ok\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "airlock_probe.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./airlock_probe.out"});
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

test "http client saasm demo builds through native exe" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/301_http_client_saasm/main.sa");
    defer std.testing.allocator.free(source_path);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const address = try std.net.Address.parseIp4("127.0.0.1", 18090);
    const server = try std.testing.allocator.create(std.net.Server);
    server.* = try address.listen(.{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);

    const body_seen = try std.testing.allocator.create(bool);
    body_seen.* = false;
    defer std.testing.allocator.destroy(body_seen);
    const server_ready = try std.testing.allocator.create(std.atomic.Value(bool));
    server_ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(server_ready);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, seen: *bool, ready: *std.atomic.Value(bool)) void {
            defer listen_server.deinit();
            ready.store(true, .release);
            var conn = listen_server.accept() catch return;
            defer conn.stream.close();

            var request_buffer: [4096]u8 = undefined;
            var http_server = std.http.Server.init(conn, &request_buffer);
            var request = http_server.receiveHead() catch return;
            const reader = request.reader() catch return;

            var body = std.ArrayList(u8).init(std.testing.allocator);
            defer body.deinit();
            if (reader.readAllArrayList(&body, 1024 * 1024)) |_| {
                seen.* = std.mem.eql(u8, body.items, "hello from saasm");
                request.respond(body.items, .{ .status = .ok }) catch return;
            } else |_| return;
        }
    }.run, .{ server, body_seen, server_ready });
    while (!server_ready.load(.acquire)) std.time.sleep(1 * std.time.ns_per_ms);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "http_client_saasm.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExitWithEnvMap(std.testing.allocator, &[_][]const u8{"./http_client_saasm.out"}, null);
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| {
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
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/302_http_server_saasm/main.sa");
    defer std.testing.allocator.free(source_path);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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
                const conn = std.net.tcpConnectToHost(std.testing.allocator, "127.0.0.1", 18091) catch |err| switch (err) {
                    error.ConnectionRefused => {
                        std.time.sleep(20 * std.time.ns_per_ms);
                        continue;
                    },
                    else => return,
                };
                defer conn.close();

                conn.writeAll(
                    "GET /stream HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n",
                ) catch return;

                var buf: [256]u8 = undefined;
                var response = std.ArrayList(u8).init(std.testing.allocator);
                defer response.deinit();
                while (true) {
                    const n = conn.read(&buf) catch return;
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
        .Exited => |code| {
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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

test "sa test covers include macro expansion fixture" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/include_macro_expand_unit.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/module_path_macro_unit.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_basic.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), include_ignored_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] active case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] ignored case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 2 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const source_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, source_path, 1024 * 1024);
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), signal_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "terminated by signal"));
}

test "sa test schedules native tests in parallel when jobs are higher" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_jobs_parallel.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const serial_start = std.time.nanoTimestamp();
    const serial_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const serial_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        serial_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    const serial_elapsed: i128 = std.time.nanoTimestamp() - serial_start;
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

    const parallel_start = std.time.nanoTimestamp();
    const parallel_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "4" };
    const parallel_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        parallel_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    const parallel_elapsed: i128 = std.time.nanoTimestamp() - parallel_start;
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
    try writeSource(tmp.dir, "fallible.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "fallible.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "fallible.sa", "-o", "fallible.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile("fallible.out.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "extern u64 fallible return can be loaded from ABI payload offset" {
    const source =
        \\@extern sa_fs_read_file(&path: ptr, path_len: u64, max_bytes: u64) -> u64!
        \\@extern sa_fs_read_buffer_data(buffer: u64) -> &ptr
        \\@extern sa_fs_read_buffer_len(buffer: u64) -> u64
        \\@extern sa_fs_read_buffer_free(^buffer: u64) -> i32
        \\
        \\@const PROBE_PATH = utf8:"probe.env"
        \\
        \\@main() -> i32!:
        \\L_ENTRY:
        \\    path_tmp = *PROBE_PATH
        \\    read_res = call @sa_fs_read_file(&path_tmp, 9, 1024)
        \\    !path_tmp
        \\    read_status = load read_res+0 as i32
        \\    handle = load read_res+8 as u64
        \\    !read_res
        \\    read_ok = eq read_status, 0
        \\    !read_status
        \\    br read_ok -> L_CHECK_LEN, L_FAIL_READ
        \\
        \\L_CHECK_LEN:
        \\    !read_ok
        \\    len = call @sa_fs_read_buffer_len(handle)
        \\    len_ok = eq len, 11
        \\    !len
        \\    br len_ok -> L_CHECK_CONTENT, L_FAIL_LEN
        \\
        \\L_CHECK_CONTENT:
        \\    !len_ok
        \\    data = call @sa_fs_read_buffer_data(handle)
        \\    first = load data+0 as u8
        \\    sixth = load data+5 as u8
        \\    first_ok = eq first, 80
        \\    sixth_ok = eq sixth, 50
        \\    content_ok = and first_ok, sixth_ok
        \\    !first
        \\    !sixth
        \\    !first_ok
        \\    !sixth_ok
        \\    !data
        \\    br content_ok -> L_FREE, L_FAIL_CONTENT
        \\
        \\L_FREE:
        \\    !content_ok
        \\    free_status = call @sa_fs_read_buffer_free(^handle)
        \\    free_ok = eq free_status, 0
        \\    !free_status
        \\    br free_ok -> L_PASS, L_FAIL_FREE
        \\
        \\L_PASS:
        \\    !free_ok
        \\    return 0
        \\
        \\L_FAIL_READ:
        \\    !read_ok
        \\    !handle
        \\    panic(121)
        \\
        \\L_FAIL_LEN:
        \\    !len_ok
        \\    !handle
        \\    panic(122)
        \\
        \\L_FAIL_CONTENT:
        \\    !content_ok
        \\    !handle
        \\    panic(123)
        \\
        \\L_FAIL_FREE:
        \\    !free_ok
        \\    panic(124)
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "fallible_u64_file.sa", source);
    try writeBytes(tmp.dir, "probe.env", "PORT=28080\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "fallible_u64_file.sa", "-o", "fallible_u64_file.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible_u64_file.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("fallible u64 ABI probe failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "result unwrap_or and map_or helpers branch on tags correctly" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const result_layout_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/result.sal");
    defer std.testing.allocator.free(result_layout_path);
    const result_src_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/result.sa");
    defer std.testing.allocator.free(result_src_path);
    const panic_src_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/panic.sa");
    defer std.testing.allocator.free(panic_src_path);

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\@import "{s}"
        \\@import "{s}"
        \\
        \\@double(x: u64) -> u64:
        \\L_ENTRY:
        \\    y = mul x, 2
        \\    return y
        \\@fallback() -> u64:
        \\L_ENTRY:
        \\    return 99
        \\@main() -> i32:
        \\L_ENTRY:
        \\    ok_res = alloc Result_SIZE
        \\    EXPAND RESULT_SET_OK ok_res, 7
        \\    err_res = alloc Result_SIZE
        \\    EXPAND RESULT_SET_ERR err_res, 3
        \\    EXPAND RESULT_UNWRAP_OR ok_unwrap, ok_res, 1
        \\    EXPAND RESULT_UNWRAP_OR err_unwrap, err_res, 5
        \\    EXPAND RESULT_MAP_OR ok_map, ok_res, @double, 1
        \\    EXPAND RESULT_MAP_OR err_map, err_res, @double, 3
        \\    EXPAND RESULT_MAP_OR_ELSE ok_map_else, ok_res, @double, @fallback
        \\    EXPAND RESULT_MAP_OR_ELSE err_map_else, err_res, @double, @fallback
        \\    sum1 = add ok_unwrap, err_unwrap
        \\    sum2 = add ok_map, err_map
        \\    sum3 = add ok_map_else, err_map_else
        \\    sum12 = add sum1, sum2
        \\    total = add sum12, sum3
        \\    !sum1
        \\    !sum2
        \\    !sum3
        \\    !sum12
        \\    !ok_unwrap
        \\    !err_unwrap
        \\    !ok_map
        \\    !err_map
        \\    !ok_map_else
        \\    !err_map_else
        \\    !ok_res
        \\    !err_res
        \\    return total
    , .{ result_layout_path, result_src_path, panic_src_path });
    defer std.testing.allocator.free(source);

    try writeSource(tmp.dir, "result_helpers.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "result_helpers.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 142), run_code);
}

test "const pointer stores survive load and print end to end" {
    const source =
        \\@import "sa_std/io/print.sai"
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
    try writeSource(tmp.dir, "const_ptr_store.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "const_ptr_store.sa", "-o", "const_ptr_store.out" };
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
        \\@import "sa_std/io/print.sai"
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
    try writeSource(tmp.dir, "vtable_indirect.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "vtable_indirect.sa", "-o", "vtable_indirect.out" };
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

test "bc2sa translates real llvm bitcode" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "sample.ll",
        \\define i32 @main(i32 %lhs, i32 %rhs) {
        \\entry:
        \\  %0 = add i32 %lhs, %rhs
        \\  %1 = icmp sgt i32 %0, 2
        \\  br i1 %1, label %ok, label %err
        \\ok:
        \\  ret i32 %0
        \\err:
        \\  ret i32 0
        \\}
        \\
    );

    const as_result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "llvm-as-14", "sample.ll", "-o", "sample.bc" },
    }) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(as_result.stdout);
    defer std.testing.allocator.free(as_result.stderr);
    switch (as_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const bc2sa_argv = [_][]const u8{ "sa", "bc2sa", "sample.bc" };
    const bc2sa_code = try saasm.cli.executeWithWriters(std.testing.allocator, bc2sa_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), bc2sa_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "@export main(lhs: i32, rhs: i32) -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "r0 = add lhs, rhs") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "br r1 -> L_ok, L_err") != null);
}

test "bc2sa translates clang cmake bitcode demo" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const demo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, "demos/bc2sa_cmake");
    defer std.testing.allocator.free(demo_root);

    const build_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(build_dir);

    const cmake_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "cmake", "-S", demo_root, "-B", build_dir },
    });
    defer std.testing.allocator.free(cmake_result.stdout);
    defer std.testing.allocator.free(cmake_result.stderr);
    switch (cmake_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    const build_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "cmake", "--build", build_dir, "--target", "bc" },
    });
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);
    switch (build_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const bc_path = try std.fs.path.join(std.testing.allocator, &.{ build_dir, "main.bc" });
    defer std.testing.allocator.free(bc_path);

    const bc2sa_argv = [_][]const u8{ "sa", "bc2sa", bc_path };
    const bc2sa_code = try saasm.cli.executeWithWriters(std.testing.allocator, bc2sa_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), bc2sa_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "@export demo(arg0: i32, arg1: i32) -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "@export scale(arg0: i32) -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "sgt r10, 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "call @scale(r13)") != null);
}

test "bc2sa rejects static stack buffer overflow in clang cmake demo" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const demo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, "demos/bc2sa_cmake");
    defer std.testing.allocator.free(demo_root);

    const build_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(build_dir);

    const cmake_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "cmake", "-S", demo_root, "-B", build_dir },
    });
    defer std.testing.allocator.free(cmake_result.stdout);
    defer std.testing.allocator.free(cmake_result.stderr);
    switch (cmake_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    const build_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "cmake", "--build", build_dir, "--target", "bc" },
    });
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);
    switch (build_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    try writeSource(tmp.dir, "vulnerable.c",
        \\void hack_me(void) {
        \\    char buffer[8];
        \\    buffer[10] = 'A';
        \\}
    );

    const clang_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "clang", "-std=c11", "-O0", "-emit-llvm", "-c", "vulnerable.c", "-o", "vulnerable.bc" },
    });
    defer std.testing.allocator.free(clang_result.stdout);
    defer std.testing.allocator.free(clang_result.stderr);
    switch (clang_result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const bc2sa_argv = [_][]const u8{ "sa", "bc2sa", "vulnerable.bc" };
    const bc2sa_code = try saasm.cli.executeWithWriters(std.testing.allocator, bc2sa_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 1), bc2sa_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "SA-CLI-019"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "static memory overflow detected"));
}

test "import expansion keeps source paths alive end to end" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/40_impl_block_state/main.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "impl_block_state.out" };
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

    try writeSource(tmp.dir, "atomic.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "atomic.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 11), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "atomic.sa", "-o", "atomic.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile("atomic.out.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./atomic.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 11), code),
        else => return error.TestUnexpectedResult,
    }

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "atomic.sa", "-o", "atomic.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_file = try tmp.dir.openFile("atomic.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "atomic.sa", "-o", "atomic.o" };
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

    try writeSource(tmp.dir, "ptr_add.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "ptr_add.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 65), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "ptr_add.sa", "-o", "ptr_add.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile("ptr_add.out.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic_native.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "panic_native.sa", "-o", "panic_native.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile("panic_native.out.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./panic_native.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 205), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.containsAtLeast(u8, exe_result.stderr, 1, "PANIC[77]: hi"));

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "panic_native.sa", "-o", "panic_native.wasm", "--target", "wasm32" };
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
    try writeSource(tmp.dir, "contracts.sa", source);

    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "contracts.sa", "-o", "contracts.o" };
    const code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), code);

    const artifact_file = try tmp.dir.openFile("contracts.o.sa.bc", .{});
    defer artifact_file.close();
    const artifact_bytes = try artifact_file.readToEndAlloc(std.testing.allocator, 1 << 20);
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "unsupported_sys.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "unsupported_sys.sa", "-o", "unsupported_sys.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unsupported_sys.out.sa.bc", .{}));
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
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/unknown_register.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "unknown_register.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unknown_register.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnknownRegister\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1007"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"register\":\"ghost\""));
}

test "memory leak demo is rejected with structured trap output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/memory_leak.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "memory_leak.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("memory_leak.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"MemoryLeak\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1012"));
}

test "fallthrough demo is rejected without a terminator" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/fallthrough.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "fallthrough.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("fallthrough.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"FallthroughForbidden\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1014"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "function body ended without a terminator"));
}

test "duplicate label demo is rejected with structured trap output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/duplicate_label.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "duplicate_label.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("duplicate_label.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"DuplicateLabel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1003"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "label is already defined"));
}

test "phi conflict demo is rejected on mismatched join states" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_conflict.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "phi_conflict.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("phi_conflict.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"PhiStateConflict\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1015"));
}

test "phi join AND demo runs through the join point" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_join_and.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "phi_join_and.out" };
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

test "build-wasm supports wasm64 freestanding no-entry" {
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
    try writeSource(tmp.dir, "wasm64.sa", source);

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "wasm64.sa", "-o", "wasm64.wasm", "--target", "wasm64" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const wasm_file = try tmp.dir.openFile("wasm64.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
    const import_names = try wasmImportNames(wasm_bytes, std.testing.allocator);
    defer std.testing.allocator.free(import_names);
    try std.testing.expectEqual(@as(usize, 0), import_names.len);
}

test "db cli init writes iface and table lifecycle commands update storage" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "flash_sale.sadb-schema",
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8 // u64
        \\#def COL_PRICE_STRIDE = 4 // f32
    );
    try writeSource(tmp.dir, "rows.csv",
        \\ID,PRICE
        \\1,9.5
        \\2,10.25
    );
    try writeSource(tmp.dir, "more.jsonl",
        \\{"ID":3,"PRICE":11.75}
    );

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const init_argv = [_][]const u8{ "sa", "db", "init", "flash_sale.sadb-schema" };
    const init_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        init_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), init_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "flash_sale.iface"));

    const iface_file = try tmp.dir.openFile("flash_sale.iface", .{});
    defer iface_file.close();
    const iface_bytes = try iface_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(iface_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def MAX_ROWS = 10"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def TABLE_ROW_BYTES = 12"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iface_bytes, 1, "#def flash_sale_ROW_BYTES = 12"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ingest_argv = [_][]const u8{ "sa", "db", "ingest", "flash_sale", "rows.csv" };
    const ingest_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ingest_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), ingest_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 2"));

    const meta_file = try tmp.dir.openFile("flash_sale.meta", .{});
    defer meta_file.close();
    const meta_bytes = try meta_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(meta_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, meta_bytes, 1, "\"row_count\":2"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const snapshot_argv = [_][]const u8{ "sa", "db", "snapshot", "flash_sale" };
    const snapshot_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        snapshot_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), snapshot_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "epoch: 1"));
    const snapshot_meta = try tmp.dir.openFile(".sa/db/snapshots/flash_sale/1/flash_sale.meta", .{});
    defer snapshot_meta.close();

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const second_ingest_argv = [_][]const u8{ "sa", "db", "ingest", "flash_sale", "more.jsonl" };
    const second_ingest_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        second_ingest_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), second_ingest_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 3"));

    const updated_meta_file = try tmp.dir.openFile("flash_sale.meta", .{});
    defer updated_meta_file.close();
    const updated_meta_bytes = try updated_meta_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(updated_meta_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, updated_meta_bytes, 1, "\"row_count\":3"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const verify_argv = [_][]const u8{ "sa", "db", "verify", "flash_sale" };
    const verify_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        verify_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), verify_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 3"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const compact_argv = [_][]const u8{ "sa", "db", "compact", "flash_sale" };
    const compact_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        compact_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), compact_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "segment_count: 1"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const restore_argv = [_][]const u8{ "sa", "db", "restore", "flash_sale", "1" };
    const restore_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        restore_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), restore_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "row_count: 2"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const lock_argv = [_][]const u8{ "sa", "db", "lock", "flash_sale" };
    const lock_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        lock_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), lock_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "locked: true"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const locked_compact_argv = [_][]const u8{ "sa", "db", "compact", "flash_sale" };
    const locked_compact_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        locked_compact_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), locked_compact_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "error: Locked"));
}

test "db cli register inspect exec round trip through registry" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "simple.sadb-schema",
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8 // u64
        \\#def COL_FACTOR_STRIDE = 8 // u64
        \\#def TABLE_ROW_BYTES = 16
    );
    try writeSource(tmp.dir, "simple.query.sa",
        \\@import "simple.sadb-schema"
        \\grants [db_read:simple]
        \\@main(id: u64, factor: u64) -> u64:
        \\L_ENTRY:
        \\total = add id, factor
        \\!id
        \\!factor
        \\return total
    );

    var params = std.ArrayList(u8).init(std.testing.allocator);
    defer params.deinit();
    try params.writer().writeInt(u64, 7, .little);
    try params.writer().writeInt(u64, 5, .little);
    try writeBytes(tmp.dir, "params.bin", params.items);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const register_argv = [_][]const u8{ "sa", "db", "register", "simple.query.sa" };
    const register_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        register_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), register_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Compiled: simple.query.sa"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Registered:"));

    const hash_hex = try std.testing.allocator.dupe(u8, try extractLineValue(stdout_buffer.items, "Hash: "));
    defer std.testing.allocator.free(hash_hex);
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const inspect_argv = [_][]const u8{ "sa", "db", "inspect", hash_hex };
    const inspect_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        inspect_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), inspect_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "imports: 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "grants: 1"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const exec_argv = [_][]const u8{ "sa", "db", "exec", hash_hex, "--params", "params.bin" };
    const exec_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        exec_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 12), exec_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "layout cli prints text, json, and debug macro outputs" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const text_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u32, pos_x:f64, pos_y:f64, hp:i32" };
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

    const json_argv = [_][]const u8{ "sa", "layout", "--name", "Pair", "--fields", "head:ptr, count:u32", "--format", "json", "--target", "32" };
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

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const debug_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u64, pos:f64, active:i1", "--format", "debug" };
    const debug_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        debug_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), debug_code);
    try std.testing.expectEqualStrings(
        \\#def Entity_SIZE  = 24
        \\#def Entity_id = +0
        \\#def Entity_pos = +8
        \\#def Entity_active = +16
        \\// 7 bytes tail padding
        \\
        \\[MACRO] DEBUG_PRINT_Entity %ptr
        \\    EXPAND PRINT! "Entity { "
        \\    __dbg_Entity_id = load %ptr+Entity_id as u64
        \\    EXPAND PRINT! "id: {:u}, ", __dbg_Entity_id
        \\    !__dbg_Entity_id
        \\    __dbg_Entity_pos = load %ptr+Entity_pos as f64
        \\    EXPAND PRINT! "pos: {:f}, ", __dbg_Entity_pos
        \\    !__dbg_Entity_pos
        \\    EXPAND PRINT! "active: <unsupported:i1>"
        \\    EXPAND PRINT! " }\n"
        \\[END_MACRO]
        \\
    , stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const dict_argv = [_][]const u8{ "sa", "layout", "--name", "Entity", "--fields", "id:u64, pos:f64", "--format", "dict" };
    const dict_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        dict_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), dict_code);
    try std.testing.expectEqualStrings(
        \\#def LAYOUT_Entity_SIZE = 16
        \\#def LAYOUT_Entity_ALIGN = 8
        \\#def LAYOUT_Entity_id_OFFSET = +0
        \\#def LAYOUT_Entity_id_SIZE = 8
        \\#def LAYOUT_Entity_id_ALIGN = 8
        \\// LAYOUT_Entity_id_TYPE = u64
        \\#def LAYOUT_Entity_pos_OFFSET = +8
        \\#def LAYOUT_Entity_pos_SIZE = 8
        \\#def LAYOUT_Entity_pos_ALIGN = 8
        \\// LAYOUT_Entity_pos_TYPE = f64
        \\
    , stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "agent-first cli commands print explain fix and skills outputs" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const explain_argv = [_][]const u8{ "sa", "explain", "SA-CLI-001" };
    const explain_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        explain_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), explain_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "code: SA-CLI-001"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "title: Missing required operand"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "fix: Pass the required file, path, or operand after the command."));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const explain_json_argv = [_][]const u8{ "sa", "explain", "SA-CLI-001", "--json" };
    const explain_json_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        explain_json_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), explain_json_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"codes\":[\"SA-CLI-001\"]"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const fix_argv = [_][]const u8{ "sa", "fix", "--plan", "SA-CLI-001", "--json" };
    const fix_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        fix_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), fix_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"action\":\"add\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"plan\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const skills_argv = [_][]const u8{ "sa", "skills", "--json" };
    const skills_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        skills_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"core diagnostics\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"std runtime\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"init [path]\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"pkg install [identity]\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const skills_help_argv = [_][]const u8{ "sa", "skills", "--help" };
    const skills_help_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        skills_help_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_help_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "usage: sa skills [--json]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "scans the current sa_std root"));
}

test "sa skills writes Codex and Claude skill files for current project" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("sa_plugins/sa_plugin_deno");
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "deno",
        \\  "version": "0.1.0",
        \\  "source": { "type": "local", "path": "." },
        \\  "abi": { "plugin": 1, "saasm": ">=0.4.0" },
        \\  "artifacts": { "linux-x86_64": { "path": "zig-out/lib/libdeno.so" } },
        \\  "interfaces": { "sai": { "path": "deno.sai" }, "sal": { "path": "deno.sal" } },
        \\  "skills": ["deno.sys", "deno.env"],
        \\  "permissions": {
        \\    "fs": [{ "op": "read", "path": "$PROJECT/**" }],
        \\    "net": [{ "url": "https://*", "methods": ["GET"] }],
        \\    "env": ["HOME", "SA_*"],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {}
        \\}
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/README.md",
        \\Deno compatibility facade for env, fs, process, and HTTP bridge workflows.
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/deno.sai",
        \\@extern sa_deno_plugin_hostname(&out_ptr: ptr, &out_len: ptr) -> u32
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/deno.sal",
        \\[MACRO] DENO_HOSTNAME %out_ptr, %out_len
        \\    %out_status = call @sa_deno_plugin_hostname(&%out_ptr, &%out_len)
        \\[END_MACRO]
        \\
    );
    try tmp.dir.makePath("sa_plugins/sa_plugin_3dengines");
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_3dengines/README.md",
        \\Experimental 3D engine plugin should not be included in the common catalog.
        \\
    );

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "generated agent skills:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".codex/skills/sa/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".claude/skills/sa/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".codex/skills/sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".claude/skills/sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "std surface:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "official plugin catalog:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Rust-style string/vec/slice/option/result/core helper macros"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "optional deno/http/node/db/plugin APIs stay outside compiler std"));

    const codex_skill = try tmp.dir.readFileAlloc(std.testing.allocator, ".codex/skills/sa/SKILL.md", 16 * 1024 * 1024);
    defer std.testing.allocator.free(codex_skill);
    const claude_skill = try tmp.dir.readFileAlloc(std.testing.allocator, ".claude/skills/sa/SKILL.md", 16 * 1024 * 1024);
    defer std.testing.allocator.free(claude_skill);
    const codex_plugins_skill = try tmp.dir.readFileAlloc(std.testing.allocator, ".codex/skills/sa_plugins/SKILL.md", 16 * 1024 * 1024);
    defer std.testing.allocator.free(codex_plugins_skill);
    const claude_plugins_skill = try tmp.dir.readFileAlloc(std.testing.allocator, ".claude/skills/sa_plugins/SKILL.md", 16 * 1024 * 1024);
    defer std.testing.allocator.free(claude_plugins_skill);

    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "name: \"sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "# SA Toolchain"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "`sa build <file>`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "`sa test <file> --list`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Treat the `sa_std Surface` section below as authoritative"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "## Std Coverage Guide"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Core macro families include string, vec, slice"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust-style fs coverage includes create_dir"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust-style net coverage includes owned address handles"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust's full std::future/std::task poll"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "## sa_std Surface"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "sa.mod"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "core/slice.sa: [MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_CREATE_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_TRY_EXISTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "net.sa: [MACRO] NET_TO_SOCKET_ADDR_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "env.sa: [MACRO] ENV_ARGS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "process.sa: [MACRO] PROCESS_CHILD_ID"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_CHAR_COUNT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_TRY_CHAR_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_IS_UTF8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sai: @extern sa_str_utf8_char_at"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sai: @extern sa_str_utf8_validate"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ffi.sa: [MACRO] CSTR_TO_STR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_CURSOR_READ_TO_END"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_CURSOR_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_TAKE_READ_TO_END"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_TAKE_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "path.sa: [MACRO] PATH_TRY_FILE_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "path.sa: [MACRO] PATH_TRY_TO_STR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "mem.sa: [MACRO] MAYBE_UNINIT_U64_AS_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "mem.sa: [MACRO] MANUALLY_DROP_U64_DEREF_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] PTR_NULL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] PTR_EXPOSE_PROVENANCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] NONNULL_OFFSET_FROM_UNSIGNED_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_U64_CHECKED_ADD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_U64_BIT_WIDTH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_I64_HIGHEST_ONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "any.sa: [MACRO] ANY_REF_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sai: @extern"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "../sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_skill, 1, "Use the installed SA compiler"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_skill, 1, "## CLI Skill Sections"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "name: \"sa_plugins\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "# SA Optional Plugins"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "not proof that any plugin is installed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "sa plugin list"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno (0.1.0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "Optional plugin: install before use"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno/sa_plugin_deno/deno.sai: @extern sa_deno_plugin_hostname"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno/sa_plugin_deno/deno.sal: [MACRO] DENO_HOSTNAME"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "3dengines"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_plugins_skill, 1, "Use the optional official SA plugin catalog"));
}

test "cli audit dispatches through runtime package plugin" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("pkg");
    try writeSource(tmp.dir, "pkg/index.sa",
        \\call @sys_print(*MSG, 2)
        \\
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "pkg");
    defer std.testing.allocator.free(pkg_root);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const audit_argv = [_][]const u8{ "sa", "audit", "--format", "json", pkg_root };
    const audit_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), audit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.startsWith(u8, stdout_buffer.items, "{\"package\":"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"trust_score\":50"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"capability\":\"io_write\""));
    try std.testing.expect(!std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "audit: "));
}

test "cli audit update-lock writes project lock through package flow" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("zig-out");
    try tmp.dir.makePath("pkg");
    try writeSource(tmp.dir, "pkg/index.sa",
        \\@main() -> i32:
        \\return 0
        \\
    );

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const audit_argv = [_][]const u8{ "sa", "audit", "--update-lock", "--format", "json", "pkg" };
    const audit_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), audit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.startsWith(u8, stdout_buffer.items, "{\"package\":\"pkg\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"machine_code_sha256\":\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"created_entry\":true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"changed\":true"));

    const lock_source = try tmp.dir.readFileAlloc(std.testing.allocator, "sa.lock", 1024 * 1024);
    defer std.testing.allocator.free(lock_source);
    var lock_file = try saasm.pkg.manifest.parseLock(std.testing.allocator, lock_source);
    defer lock_file.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), lock_file.entries.len);
    try std.testing.expectEqualStrings("pkg", lock_file.entries[0].url);
    try std.testing.expectEqualStrings("HEAD", lock_file.entries[0].ref);
    try std.testing.expectEqual(@as(usize, 1), lock_file.entries[0].approved_machine_code_hashes.count());

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), second_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"created_entry\":false"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"changed\":false"));
}

test "cli init creates a binary project and install syncs manifest dependencies" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const init_argv = [_][]const u8{ "sa", "init", "app" };
    const init_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        init_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), init_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Initialized SA binary project: app"));
    try tmp.dir.access("app/sa.mod", .{ .mode = .read_only });
    try tmp.dir.access("app/src/main.sa", .{ .mode = .read_only });
    try tmp.dir.access("app/.gitignore", .{ .mode = .read_only });

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), run_code);

    try original_cwd.setAsCwd();
    try tmp.dir.setAsCwd();
    try tmp.dir.makePath("app/deps/example/pkg");
    try writeSource(tmp.dir, "app/deps/example/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/deps/example/pkg");
    defer std.testing.allocator.free(pkg_root);
    var pkg_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/pkg", "HEAD", pkg_root, &.{});
    defer pkg_report.deinit(std.testing.allocator);
    const pkg_hash_hex = std.fmt.bytesToHex(pkg_report.source_sha256, .lower);
    const manifest_source = try std.fmt.allocPrint(
        std.testing.allocator,
        "require deps/example/pkg @HEAD sha256:{s}\n",
        .{pkg_hash_hex[0..]},
    );
    defer std.testing.allocator.free(manifest_source);
    try writeSource(tmp.dir, "app/sa.mod", manifest_source);
    try app_dir.setAsCwd();
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "sa_vendor/deps/example/pkg"));
    try tmp.dir.access("app/sa_vendor/deps/example/pkg/index.sa", .{ .mode = .read_only });
    try tmp.dir.access("app/sa.sum", .{ .mode = .read_only });
}

test "workspace install aggregates member manifests at root and pkg install falls back to builtin workspace flow" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("members/app/src");
    try tmp.dir.makePath("members/tool/src");
    try tmp.dir.makePath("deps/example/shared");
    try tmp.dir.makePath("deps/example/app");
    try tmp.dir.makePath("deps/example/tool");

    try writeSource(tmp.dir, "members/app/src/main.sa",
        \\@main() -> i32:
        \\return 1
    );
    try writeSource(tmp.dir, "members/tool/src/main.sa",
        \\@main() -> i32:
        \\return 2
    );
    try writeSource(tmp.dir, "deps/example/shared/index.sa",
        \\@shared_value() -> i32:
        \\return 10
    );
    try writeSource(tmp.dir, "deps/example/app/index.sa",
        \\@app_value() -> i32:
        \\return 20
    );
    try writeSource(tmp.dir, "deps/example/tool/index.sa",
        \\@tool_value() -> i32:
        \\return 30
    );

    const shared_root = try tmp.dir.realpathAlloc(std.testing.allocator, "deps/example/shared");
    defer std.testing.allocator.free(shared_root);
    const app_root = try tmp.dir.realpathAlloc(std.testing.allocator, "deps/example/app");
    defer std.testing.allocator.free(app_root);
    const tool_root = try tmp.dir.realpathAlloc(std.testing.allocator, "deps/example/tool");
    defer std.testing.allocator.free(tool_root);

    var shared_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/shared", "HEAD", shared_root, &.{});
    defer shared_report.deinit(std.testing.allocator);
    var app_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/app", "HEAD", app_root, &.{});
    defer app_report.deinit(std.testing.allocator);
    var tool_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/tool", "HEAD", tool_root, &.{});
    defer tool_report.deinit(std.testing.allocator);

    const shared_hash = std.fmt.bytesToHex(shared_report.source_sha256, .lower);
    const app_hash = std.fmt.bytesToHex(app_report.source_sha256, .lower);
    const tool_hash = std.fmt.bytesToHex(tool_report.source_sha256, .lower);

    const root_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\workspace {{
        \\  members ["members/app", "members/tool"]
        \\  default_member "app"
        \\}}
        \\
        \\require deps/example/shared @HEAD sha256:{s}
    , .{shared_hash[0..]});
    defer std.testing.allocator.free(root_manifest_source);
    try writeSource(tmp.dir, "sa.mod", root_manifest_source);

    const app_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\package "app"
        \\
        \\require deps/example/shared @HEAD sha256:{s}
        \\require deps/example/app @HEAD sha256:{s}
    , .{ shared_hash[0..], app_hash[0..] });
    defer std.testing.allocator.free(app_manifest_source);
    try writeSource(tmp.dir, "members/app/sa.mod", app_manifest_source);

    const tool_manifest_source = try std.fmt.allocPrint(std.testing.allocator,
        \\package "tool"
        \\
        \\require deps/example/shared @HEAD sha256:{s}
        \\require deps/example/tool @HEAD sha256:{s}
    , .{ shared_hash[0..], tool_hash[0..] });
    defer std.testing.allocator.free(tool_manifest_source);
    try writeSource(tmp.dir, "members/tool/sa.mod", tool_manifest_source);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "sa_vendor/deps/example/shared"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "sa_vendor/deps/example/app"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "sa_vendor/deps/example/tool"));
    try tmp.dir.access("sa_vendor/deps/example/shared/index.sa", .{ .mode = .read_only });
    try tmp.dir.access("sa_vendor/deps/example/app/index.sa", .{ .mode = .read_only });
    try tmp.dir.access("sa_vendor/deps/example/tool/index.sa", .{ .mode = .read_only });
    try tmp.dir.access("sa.sum", .{ .mode = .read_only });

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const pkg_install_argv = [_][]const u8{ "sa", "pkg", "install", "-p", "tool" };
    const pkg_install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        pkg_install_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), pkg_install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "sa_vendor/deps/example/tool"));
}

test "package preflight rejects tampered project sum as structured trap" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/deps/example/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/deps/example/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );

    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/deps/example/pkg");
    defer std.testing.allocator.free(pkg_root);
    var pkg_report = try saasm.pkg.audit.auditPackage(std.testing.allocator, "deps/example/pkg", "HEAD", pkg_root, &.{});
    defer pkg_report.deinit(std.testing.allocator);
    const pkg_hash_hex = std.fmt.bytesToHex(pkg_report.source_sha256, .lower);
    const manifest_source = try std.fmt.allocPrint(
        std.testing.allocator,
        "require deps/example/pkg @HEAD sha256:{s}\n",
        .{pkg_hash_hex[0..]},
    );
    defer std.testing.allocator.free(manifest_source);
    try writeSource(tmp.dir, "app/sa.mod", manifest_source);

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const install_argv = [_][]const u8{ "sa", "install" };
    const install_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        install_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const bad_sum =
        \\deps/example/pkg @HEAD sha256:0000000000000000000000000000000000000000000000000000000000000000
        \\
    ;
    try writeSource(std.fs.cwd(), "sa.sum", bad_sum);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--json" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), run_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"SumHashMismatch\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"status\":\"error\""));
}

test "PkgMgr-Confirm-NonTty rejects risky package preflight before build output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/sa_vendor/risky/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/risky/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/sa_vendor/risky/pkg");
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "risky/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    var input = std.io.fixedBufferStream("");
    const build_argv = [_][]const u8{ "sa", "build-exe", "src/main.sa", "-o", "blocked.out", "--json" };
    const code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        build_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
        .{ .stdin_reader = input.reader().any(), .stdin_is_tty = false },
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"MissingTtyForConfirmation\""));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access("blocked.out", .{ .mode = .read_only }));
}

test "PkgMgr-Confirm-Tty accepts exact URL through compile preflight" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/sa_vendor/risky/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/risky/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/sa_vendor/risky/pkg");
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "risky/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    var input = std.io.fixedBufferStream("risky/pkg\n");
    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa" };
    const code = try saasm.cli.executeWithWritersAndOptions(
        std.testing.allocator,
        run_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
        .{ .stdin_reader = input.reader().any(), .stdin_is_tty = true },
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "SA ZERO-TRUST PACKAGE REVIEW REQUIRED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "type the exact package URL to continue: risky/pkg"));
}

test "PkgMgr-CI-DualTrack rejects mismatched source and unauthorized primitives" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/sa_vendor/ci/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/ci/pkg/index.sa",
        \\call @sys_net_tx(*BUF, 4)
        \\
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/sa_vendor/ci/pkg");
    defer std.testing.allocator.free(pkg_root);

    const bad_manifest =
        \\require ci/pkg @HEAD sha256:0000000000000000000000000000000000000000000000000000000000000000
        \\
    ;
    try writeSource(tmp.dir, "app/sa.mod", bad_manifest);

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_ci_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--ci", "--json" };
    var code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_ci_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UpstreamShaMismatch\""));

    try original_cwd.setAsCwd();
    try tmp.dir.setAsCwd();
    try writeManifestForPackage(tmp.dir, "app", "ci/pkg", pkg_root, "");
    try app_dir.setAsCwd();

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_ci_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnauthorizedPrimitive\""));
}

test "PkgMgr-Offline-Build uses vendored sources and project sum" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("app/src");
    try tmp.dir.makePath("app/sa_vendor/safe/pkg");
    try writeSource(tmp.dir, "app/src/main.sa",
        \\@main() -> i32:
        \\return 0
    );
    try writeSource(tmp.dir, "app/sa_vendor/safe/pkg/index.sa",
        \\@pkg_value() -> i32:
        \\return 42
    );
    const pkg_root = try tmp.dir.realpathAlloc(std.testing.allocator, "app/sa_vendor/safe/pkg");
    defer std.testing.allocator.free(pkg_root);
    try writeManifestForPackage(tmp.dir, "app", "safe/pkg", pkg_root, "");
    try writeProjectSum(tmp.dir, "app");

    var app_dir = try tmp.dir.openDir("app", .{});
    defer app_dir.close();
    try app_dir.setAsCwd();

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "src/main.sa", "--offline" };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "build and run json diagnostics emit structured success metrics on stderr" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "json_success.sa",
        \\@main() -> i32:
        \\return 7
    );

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "json_success.sa", "--json" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 7), run_code);
    try std.testing.expectEqualStrings("{\"status\":\"ok\",\"metrics\":{\"compile_tokens\":5,\"instruction_count\":2}}\n", stderr_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success.out", "--json" };
    const build_exe_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"compile_tokens\":5"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_mem_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success_mem.out", "--json", "--mem-report", "--no-incremental" };
    const build_mem_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_mem_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), build_mem_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    var mem_json = try parseJsonValue(std.testing.allocator, stderr_buffer.items);
    defer mem_json.deinit();
    const mem_metrics = try jsonObjectGet(&mem_json, "metrics");
    const memory = try jsonObjectGetValue(mem_metrics, "memory");
    const rss = try jsonObjectGetValue(memory, "rss_bytes");
    _ = try jsonObjectGetValue(rss, "start");
    _ = try jsonObjectGetValue(rss, "after_load");
    _ = try jsonObjectGetValue(rss, "after_setup");
    _ = try jsonObjectGetValue(rss, "after_flatten");
    _ = try jsonObjectGetValue(rss, "after_verify");
    _ = try jsonObjectGetValue(rss, "after_emit");
    _ = try jsonObjectGetValue(rss, "after_link");
    _ = try jsonObjectGetValue(rss, "end");
    const verifier_rss = try jsonObjectGetValue(memory, "verifier_rss_bytes");
    _ = try jsonObjectGetValue(verifier_rss, "start");
    _ = try jsonObjectGetValue(verifier_rss, "after_classify");
    _ = try jsonObjectGetValue(verifier_rss, "after_metadata");
    _ = try jsonObjectGetValue(verifier_rss, "after_chunks");
    _ = try jsonObjectGetValue(verifier_rss, "after_finalize");
    _ = try jsonObjectGetValue(memory, "peak_rss_bytes");

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_mem_text_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success_mem_text.out", "--mem-report", "--no-incremental" };
    const build_mem_text_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_mem_text_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), build_mem_text_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory stage start"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory stage verifier.after_classify"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory report (RSS)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "after_flatten"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "peak"));
}

test "graph and size cli emit structured reports for a tiny project" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("src");
    try writeSource(tmp.dir, "src/main.sa",
        \\@helper(value: i32) -> i32:
        \\    return value
        \\@main() -> i32:
        \\    value = call @helper(7)
        \\    return value
    );

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const graph_argv = [_][]const u8{ "sa", "graph", "--json" };
    const graph_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        graph_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), graph_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const graph_parsed = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer graph_parsed.deinit();
    const graph_root = try jsonObjectGet(&graph_parsed, "graph");

    const graph_value = switch (graph_root) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    const nodes_value = graph_value.get("nodes") orelse return error.TestUnexpectedResult;
    const edges_value = graph_value.get("edges") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), try jsonArrayCount(nodes_value));
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayCount(edges_value));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"source_file\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"function\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"calls\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const size_argv = [_][]const u8{ "sa", "size", "--json" };
    const size_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        size_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), size_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const size_parsed = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer size_parsed.deinit();
    const size_graph = try jsonObjectGet(&size_parsed, "functions");
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayCount(size_graph));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"name\":\"helper\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"name\":\"main\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"instruction_count\":"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"byte_count\":"));
}

test "llvmc backend compilation and verification on rosetta demos" {
    try assertBuildExeStdoutPureBc("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertBuildExeStdoutPureBc("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertBuildExeStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
}

test "agent capability: check uses verdict-only v2 cache and keeps compile containment" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const help_argv = [_][]const u8{ "sa", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "check"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "daemon"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "--affected"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{
        .sub_path = "check_v2_unique.sa",
        .data =
        \\@const CHECK_V2_SENTINEL_9B2D = utf8:"verdict-v2-cli-smoke-9b2d"
        \\@main() -> i32:
        \\return 0
        ,
    });
    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const check_source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "check_v2_unique.sa" });
    defer std.testing.allocator.free(check_source_path);

    const check1 = [_][]const u8{ "sa", "check", check_source_path, "--json" };
    const c1 = try saasm.cli.executeWithWriters(std.testing.allocator, check1[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), c1);
    var first_json = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer first_json.deinit();
    try std.testing.expectEqualStrings("ok", try jsonStringValue(try jsonObjectGet(&first_json, "status")));
    const first_metrics = try jsonObjectGet(&first_json, "metrics");
    const first_cache = try jsonObjectGetValue(first_metrics, "cache");
    try std.testing.expectEqualStrings("verify-verdict-v2", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expect((try jsonPositiveU64Value(try jsonObjectGetValue(first_metrics, "instruction_count"))) > 0);
    try std.testing.expect((try jsonPositiveU64Value(try jsonObjectGetValue(first_metrics, "compile_tokens"))) > 0);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const c2 = try saasm.cli.executeWithWriters(std.testing.allocator, check1[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), c2);
    var second_json = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer second_json.deinit();
    try std.testing.expectEqualStrings("ok", try jsonStringValue(try jsonObjectGet(&second_json, "status")));
    const second_metrics = try jsonObjectGet(&second_json, "metrics");
    const second_cache = try jsonObjectGetValue(second_metrics, "cache");
    try std.testing.expectEqualStrings("verify-verdict-v2", try jsonStringValue(try jsonObjectGetValue(second_cache, "kind")));
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const test_help = [_][]const u8{ "sa", "test", "--help" };
    const th = try saasm.cli.executeWithWriters(std.testing.allocator, test_help[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), th);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "--affected"));
}

test "agent capability: affected selects impacted tests" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // First run establishes baseline (no prior function hashes in this process).
    const first = [_][]const u8{ "sa", "test", "tests/agent_fixtures/affected_graph.sa", "--affected" };
    const code1 = try saasm.cli.executeWithWriters(std.testing.allocator, first[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), code1);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "affected:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "baseline=no") or std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "selected_tests"));

    // Second identical run must not use the unsound whole-source pass cache.
    // Until the affected namespace and dependency graph are complete, an empty
    // impacted set falls back to executing the requested tests.
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const code2 = try saasm.cli.executeWithWriters(std.testing.allocator, first[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), code2);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "source-pass-cache") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "no impacted tests; skipped") == null);
}

test "affected test cache metrics are reported after successful run" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "affected_cache_metrics.sa",
        \\@helper() -> i32:
        \\L_ENTRY:
        \\    return 1
        \\
        \\@test "affected cache metrics"():
        \\L_ENTRY:
        \\    call @helper()
        \\    return
    );

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", "affected_cache_metrics.sa", "--affected", "--jobs", "1", "--json" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, argv[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"affected\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buffer.items);
    defer first_json.deinit();
    const first_cache = try jsonObjectGetValue(try jsonObjectGet(&first_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));
    try std.testing.expectEqualStrings("absent", try jsonStringValue(try jsonObjectGetValue(first_cache, "reason")));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, argv[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"affected\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    var second_json = try parseJsonValue(std.testing.allocator, stderr_buffer.items);
    defer second_json.deinit();
    const second_cache = try jsonObjectGetValue(try jsonObjectGet(&second_json, "metrics"), "cache");
    try std.testing.expectEqualStrings("test", try jsonStringValue(try jsonObjectGetValue(second_cache, "kind")));
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));
    try std.testing.expectEqualStrings("hit", try jsonStringValue(try jsonObjectGetValue(second_cache, "reason")));
}

test "affected baseline is committed only after tests pass" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const source =
        \\@test "phase minus one failed baseline sentinel 7f42"():
        \\L_FAIL:
        \\    panic(99)
    ;
    try tmp.dir.writeFile(.{ .sub_path = "affected_failure.sa", .data = source });
    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "affected_failure.sa" });
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const argv = [_][]const u8{ "sa", "test", source_path, "--affected", "--jobs", "1" };

    const first_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expect(first_code != 0);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expect(second_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "source-pass-cache") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "no impacted tests; skipped") == null);
}
