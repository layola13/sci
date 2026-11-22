const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const writeBytes = helpers.writeBytes;
const singleCacheEntryName = helpers.singleCacheEntryName;
const cacheEntryCount = helpers.cacheEntryCount;
const expectNoTextLlvmArtifacts = helpers.expectNoTextLlvmArtifacts;
const runCommandAnyExit = helpers.runCommandAnyExit;

test "sa test compile-only reuses and repairs project test cache" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@test "cached test compile"():
        \\L_ENTRY:
        \\    return
    ;
    try writeSource(tmp.dir, "cached_test.sa", source);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const test_argv = [_][]const u8{ "sa", "test", "cached_test.sa", "--compile-only", "--jobs", "1" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
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
    try tmp.dir.access(std.testing.io, cached_manifest, .{});
    const metadata_bytes = try tmp.dir.readFileAlloc(std.testing.io, cached_metadata, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(metadata_bytes);
    try std.testing.expect(std.mem.indexOf(u8, metadata_bytes, "cached test compile") != null);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const cached_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), cached_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));

    try tmp.dir.deleteFile(std.testing.io, cached_output);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));
    try tmp.dir.access(std.testing.io, cached_output, .{});

    try writeBytes(tmp.dir, cached_manifest, "{\"version\":1,\"kind\":\"test\",\"key\":\"bad\"}\n");
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const third_code = try saasm.cli.executeWithWriters(std.testing.allocator, test_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), third_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expectEqual(@as(usize, 1), try cacheEntryCount(tmp.dir, ".sa_cache/test"));
    const repaired_manifest = try tmp.dir.readFileAlloc(std.testing.io, cached_manifest, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(repaired_manifest);
    try std.testing.expect(std.mem.indexOf(u8, repaired_manifest, cache_key) != null);
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
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
    const serial_artifact = try tmp.dir.openFile(std.testing.io, serial_artifact_path, .{});
    defer serial_artifact.close(std.testing.io);
    const serial_artifact_bytes = try sio.readToEndAlloc(serial_artifact, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(serial_artifact_bytes);

    const auto_artifact = try tmp.dir.openFile(std.testing.io, auto_artifact_path, .{});
    defer auto_artifact.close(std.testing.io);
    const auto_artifact_bytes = try sio.readToEndAlloc(auto_artifact, std.testing.allocator, 1 << 20);
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "unused_sort_import.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "unused_sort_import.sa", "-o", "unused_sort_import.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "unused_sort_import.out.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);
}

test "json extern build-exe does not inject debug prints" {
    const source =
        \\@import "sa_std/encoding/json.sa"
        \\
        \\@const DOC = utf8:"{\"name\":\"sci\"}"
        \\#def DOC_LEN = 14
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    root = call @sa_json_parse(&DOC, DOC_LEN)
        \\    parse_ok = ne root, 0
        \\    br parse_ok -> L_KIND, L_FAIL_PARSE
        \\
        \\L_FAIL_PARSE:
        \\    !root
        \\    !parse_ok
        \\    return 10
        \\
        \\L_KIND:
        \\    kind = call @sa_json_kind(root)
        \\    kind_ok = eq kind, SA_JSON_KIND_OBJECT
        \\    !kind
        \\    br kind_ok -> L_FREE, L_FAIL_KIND
        \\
        \\L_FAIL_KIND:
        \\    free_res = call @sa_json_free(^root)
        \\    !free_res
        \\    !parse_ok
        \\    !kind_ok
        \\    return 11
        \\
        \\L_FREE:
        \\    free_res = call @sa_json_free(^root)
        \\    !free_res
        \\    !parse_ok
        \\    !kind_ok
        \\    return 0
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "json_debug_clean.sa", source);

    var build_stdout = std.array_list.Managed(u8).init(std.testing.allocator);
    defer build_stdout.deinit();
    var build_stderr = std.array_list.Managed(u8).init(std.testing.allocator);
    defer build_stderr.deinit();

    const build_exe_argv = [_][]const u8{
        "sa",
        "build-exe",
        "json_debug_clean.sa",
        "-o",
        "json_debug_clean.out",
        "--jobs",
        "1",
        "--no-incremental",
    };
    const build_exe_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&build_stdout),
        sio.managedWriter(&build_stderr),
    );
    if (build_exe_code != 0) {
        std.debug.print("json debug-clean build failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ build_stdout.items, build_stderr.items });
    }
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);
    try std.testing.expectEqual(@as(usize, 0), build_stdout.items.len);
    try std.testing.expectEqual(@as(usize, 0), build_stderr.items.len);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./json_debug_clean.out"});
    defer std.testing.allocator.free(native_result.stdout);
    defer std.testing.allocator.free(native_result.stderr);
    switch (native_result.term) {
        .exited => |code| {
            if (code != 0 or native_result.stdout.len != 0 or native_result.stderr.len != 0) {
                std.debug.print("json debug-clean native failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ native_result.stdout, native_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => |term| {
            std.debug.print("json debug-clean native terminated unexpectedly: {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ term, native_result.stdout, native_result.stderr });
            return error.TestUnexpectedResult;
        },
    }
    try std.testing.expectEqual(@as(usize, 0), native_result.stdout.len);
    try std.testing.expectEqual(@as(usize, 0), native_result.stderr.len);
    try std.testing.expect(std.mem.indexOf(u8, native_result.stderr, "DBG parse") == null);
    try std.testing.expect(std.mem.indexOf(u8, native_result.stderr, "DBG object_get") == null);
    try std.testing.expect(std.mem.indexOf(u8, native_result.stderr, "DBG kind") == null);
    try std.testing.expect(std.mem.indexOf(u8, native_result.stderr, "DBG string_") == null);
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "parallel_trap.sa", source);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "parallel_trap.sa", "--jobs", "2" };
    const code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "\"trap\":\"UnknownRegister\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "return first_missing"));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buf.items, "return second_missing") == null);
}
