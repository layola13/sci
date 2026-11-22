const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const parseJsonValue = helpers.parseJsonValue;
const jsonObjectGet = helpers.jsonObjectGet;
const jsonObjectGetValue = helpers.jsonObjectGetValue;
const jsonBoolValue = helpers.jsonBoolValue;
const jsonStringValue = helpers.jsonStringValue;
const writeSource = helpers.writeSource;
const writeBytes = helpers.writeBytes;
const writeCacheManifest = helpers.writeCacheManifest;
const freeStringMtimeMap = helpers.freeStringMtimeMap;
const cachedFunctionObjectMtimes = helpers.cachedFunctionObjectMtimes;
const cachedFunctionManifestCount = helpers.cachedFunctionManifestCount;
const runCommandAnyExit = helpers.runCommandAnyExit;

test "cli run/build-exe/build-wasm produce real artifacts" {
    const source =
        \\#loc "hello.rs":10:4
        \\@ffi_wrapper probe_fallible_i32_wire() -> i32:
        \\node = alloc 8
        \\!node
        \\return 7
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "sample.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "sample.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 7), run_code);

    const exe_path = "sample.out";
    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "sample.sa", "-o", exe_path, "-g" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe = try tmp.dir.openFile(std.testing.io, exe_path, .{});
    const exe_bytes = try sio.readToEndAlloc(exe, std.testing.allocator, 1 << 20);
    exe.close(std.testing.io);
    defer std.testing.allocator.free(exe_bytes);
    try std.testing.expect(exe_bytes.len > 0);

    const artifact_path = "sample.out.sa.bc";
    const artifact = try tmp.dir.openFile(std.testing.io, artifact_path, .{});
    const artifact_bytes = try sio.readToEndAlloc(artifact, std.testing.allocator, 1 << 20);
    artifact.close(std.testing.io);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    try tmp.dir.deleteFile(std.testing.io, exe_path);
    try tmp.dir.deleteFile(std.testing.io, artifact_path);
    const cached_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), cached_exe_code);
    const cached_artifact = try tmp.dir.openFile(std.testing.io, artifact_path, .{});
    cached_artifact.close(std.testing.io);
    if (builtin.os.tag != .windows) {
        const cached_exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./sample.out"});
        defer std.testing.allocator.free(cached_exe_result.stdout);
        defer std.testing.allocator.free(cached_exe_result.stderr);
        switch (cached_exe_result.term) {
            .exited => |code| try std.testing.expectEqual(@as(u8, 7), code),
            else => return error.TestUnexpectedResult,
        }
    }

    const obj_path = "sample.o";
    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "sample.sa", "--jobs", "auto", "-o", obj_path };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj = try tmp.dir.openFile(std.testing.io, obj_path, .{});
    defer obj.close(std.testing.io);
    const obj_bytes = try sio.readToEndAlloc(obj, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const wasm_path = "sample.wasm";
    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "sample.sa", "--jobs", "auto", "-o", wasm_path, "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile(std.testing.io, wasm_path, .{});
    defer wasm.close(std.testing.io);
    const wasm_bytes = try sio.readToEndAlloc(wasm, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}

test "cli default executable suffix is target aware" {
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqualStrings(".exe", saasm.cli.defaultExecutableSuffix());
    } else {
        try std.testing.expectEqualStrings("", saasm.cli.defaultExecutableSuffix());
    }
}

test "llvm disabled build-exe reports backend diagnostic" {
    if (saasm.build_options.llvm_enabled) return error.SkipZigTest;

    const source =
        \\@main() -> i32:
        \\return 0
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "minimal.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "minimal.sa" };
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
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "error[LLVMBackend]: llvmc backend: LLVM-C backend is disabled in this build"));

    const default_out = try std.fmt.allocPrint(std.testing.allocator, "minimal{s}", .{saasm.cli.defaultExecutableSuffix()});
    defer std.testing.allocator.free(default_out);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, default_out, .{}));
}

test "cli build-obj incremental reuses local cache layout" {
    const source =
        \\@helper(value: i32) -> i32:
        \\return value + 1
        \\
        \\@main() -> i32:
        \\value = call @helper(6)
        \\return value
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "incremental.sa", source);

    const build_argv = [_][]const u8{ "sa", "build-obj", "incremental.sa", "--incremental", "-o", "incremental.o" };
    const first_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), first_code);
    const second_code = try saasm.cli.execute(std.testing.allocator, build_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), second_code);

    var before_mtimes = try cachedFunctionObjectMtimes(std.testing.allocator, tmp.dir);
    defer freeStringMtimeMap(std.testing.allocator, &before_mtimes);
    try std.testing.expectEqual(@as(u32, 2), before_mtimes.count());

    const modified_source =
        \\@helper(value: i32) -> i32:
        \\return value + 2
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
    try std.testing.expect(after_mtimes.count() >= 3);

    var reused_count: usize = 0;
    var before_iter = before_mtimes.iterator();
    while (before_iter.next()) |entry| {
        if (after_mtimes.get(entry.key_ptr.*)) |mtime| {
            if (mtime == entry.value_ptr.*) reused_count += 1;
        }
    }
    try std.testing.expect(reused_count >= 1);

    const obj_file = try tmp.dir.openFile(std.testing.io, "incremental.o", .{});
    defer obj_file.close(std.testing.io);
    const obj_bytes = try sio.readToEndAlloc(obj_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const bc_file = try tmp.dir.openFile(std.testing.io, "incremental.o.sa.bc", .{});
    defer bc_file.close(std.testing.io);
    const bc_bytes = try sio.readToEndAlloc(bc_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(bc_bytes);
    try std.testing.expect(bc_bytes.len > 0);

    var cache_dir = try tmp.dir.openDir(std.testing.io, ".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_dir.close();
    var cache_iter = cache_dir.iterate();
    try std.testing.expect((try cache_iter.next()) != null);
    try std.testing.expect(try cachedFunctionManifestCount(tmp.dir) >= 1);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const help_argv = [_][]const u8{ "sa", "build-obj", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--incremental") != null);
}

test "cli build project cache is default and can be disabled" {
    const source =
        \\@main() -> i32:
        \\return 9
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "cached.sa", source);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const build_argv = [_][]const u8{ "sa", "build-exe", "cached.sa", "-o", "cached.out", "--json", "--profile" };
    const first_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), first_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    var first_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer first_json.deinit();
    const first_metrics = try jsonObjectGet(&first_json, "metrics");
    const first_cache = try jsonObjectGetValue(first_metrics, "cache");
    try std.testing.expectEqualStrings("build-exe", try jsonStringValue(try jsonObjectGetValue(first_cache, "kind")));
    try std.testing.expectEqual(false, try jsonBoolValue(try jsonObjectGetValue(first_cache, "hit")));

    try tmp.dir.deleteFile(std.testing.io, "cached.out");
    try tmp.dir.deleteFile(std.testing.io, "cached.out.sa.bc");
    stderr_buf.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(std.testing.allocator, build_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), second_code);
    var second_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer second_json.deinit();
    const second_metrics = try jsonObjectGet(&second_json, "metrics");
    const second_cache = try jsonObjectGetValue(second_metrics, "cache");
    try std.testing.expectEqual(true, try jsonBoolValue(try jsonObjectGetValue(second_cache, "hit")));

    stderr_buf.clearRetainingCapacity();
    const no_cache_argv = [_][]const u8{ "sa", "build-exe", "cached.sa", "-o", "cached_no_cache.out", "--json", "--profile", "--no-incremental" };
    const no_cache_code = try saasm.cli.executeWithWriters(std.testing.allocator, no_cache_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), no_cache_code);
    var no_cache_json = try parseJsonValue(std.testing.allocator, stderr_buf.items);
    defer no_cache_json.deinit();
    const no_cache_metrics = try jsonObjectGet(&no_cache_json, "metrics");
    try std.testing.expectError(error.TestUnexpectedResult, jsonObjectGetValue(no_cache_metrics, "cache"));

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const help_argv = [_][]const u8{ "sa", "build-exe", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--no-incremental") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--mem-report") != null);
}

test "cli build-exe cache key separates plain and release-small" {
    // Same-directory plain build followed by --release-small must
    // NOT return the plain binary: the two optimization levels
    // emit different binaries (O0 vs O1), so their cache keys must
    // differ. The probe program is a small sum-of-squares loop whose
    // plain and --release-small binaries differ by hash and size
    // (verified: 542,944 B vs 540,840 B on the pristine host).
    const source =
        \\@main() -> i32:
        \\L_ENTRY:
        \\    total_slot = stack_alloc 8
        \\    store total_slot+0, 0 as u32
        \\    i_slot = stack_alloc 8
        \\    store i_slot+0, 0 as u32
        \\    jmp L_COND
        \\L_COND:
        \\    i = load i_slot+0 as u32
        \\    more = ult i, 100000
        \\    br more -> L_BODY, L_END
        \\L_BODY:
        \\    total = load total_slot+0 as u32
        \\    sq = mul i, i
        \\    next_total = add total, sq
        \\    store total_slot+0, next_total as u32
        \\    next_i = add i, 1
        \\    store i_slot+0, next_i as u32
        \\    !total
        \\    !sq
        \\    !next_total
        \\    !next_i
        \\    !i
        \\    !more
        \\    jmp L_COND
        \\L_END:
        \\    !i
        \\    !more
        \\    result = load total_slot+0 as u32
        \\    !result
        \\    return result
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "optdisc.sa", source);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const plain_argv = [_][]const u8{ "sa", "build-exe", "optdisc.sa", "-o", "plain.bin" };
    const plain_code = try saasm.cli.executeWithWriters(std.testing.allocator, plain_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), plain_code);
    const plain_bytes = try tmp.dir.readFileAlloc(std.testing.io, "plain.bin", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(plain_bytes);
    var plain_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(plain_bytes, &plain_hash, .{});

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const rs_argv = [_][]const u8{ "sa", "build-exe", "optdisc.sa", "-o", "rs.bin", "--release-small" };
    const rs_code = try saasm.cli.executeWithWriters(std.testing.allocator, rs_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), rs_code);
    const rs_bytes = try tmp.dir.readFileAlloc(std.testing.io, "rs.bin", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(rs_bytes);
    var rs_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(rs_bytes, &rs_hash, .{});

    // The two binaries must differ: equal hashes mean the cache
    // served the plain binary for the --release-small request.
    try std.testing.expect(!std.mem.eql(u8, &plain_hash, &rs_hash));
}

test "cli cache clean removes invalid project cache entries" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const good_key = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const incomplete_key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const corrupt_manifest_key = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    try tmp.dir.createDirPath(std.testing.io, ".sa_cache/build-exe/" ++ good_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ good_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ good_key, "build-exe", good_key, "bc", "exe");
    try tmp.dir.createDirPath(std.testing.io, ".sa_cache/build-exe/" ++ incomplete_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ incomplete_key ++ "/artifact.sa.bc", "bc");
    try tmp.dir.createDirPath(std.testing.io, ".sa_cache/build-exe/" ++ corrupt_manifest_key);
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key ++ "/artifact.sa.bc", "bc");
    try writeBytes(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key ++ "/output.bin", "exe");
    try writeCacheManifest(tmp.dir, ".sa_cache/build-exe/" ++ corrupt_manifest_key, "build-exe", corrupt_manifest_key, "bc", "wrong-output");
    try tmp.dir.createDirPath(std.testing.io, ".sa_cache/test/not-a-hex-key");

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const clean_argv = [_][]const u8{ "sa", "cache", "clean", "--max-age-days", "0" };
    const clean_code = try saasm.cli.executeWithWriters(std.testing.allocator, clean_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), clean_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "cache clean: scanned=4 removed=3 kept=1"));

    try tmp.dir.access(std.testing.io, ".sa_cache/build-exe/" ++ good_key ++ "/output.bin", .{});
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, ".sa_cache/build-exe/" ++ incomplete_key, .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, ".sa_cache/build-exe/" ++ corrupt_manifest_key, .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, ".sa_cache/test/not-a-hex-key", .{}));

    stdout_buf.clearRetainingCapacity();
    const help_argv = [_][]const u8{ "sa", "cache", "clean", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "--max-age-days") != null);
}

test "cli pkg add records the require line and pkg list reads it back" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "deps/example/shared");
    try writeSource(tmp.dir, "deps/example/shared/index.sa",
        \\@shared_value() -> i32:
        \\return 10
    );
    try writeSource(tmp.dir, "sa.mod",
        \\package "demo"
        \\
    );

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const add_argv = [_][]const u8{ "sa", "pkg", "add", "deps/example/shared" };
    const add_code = try saasm.cli.executeWithWriters(std.testing.allocator, add_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    if (add_code != 0) {
        std.debug.print("pkg add failed: code={d}\nstdout:\n{s}\nstderr:\n{s}\n", .{ add_code, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), add_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "pkg add: deps/example/shared @HEAD sha256:"));

    const mod_text = try sio.cwd().readFileAlloc(std.testing.allocator, "sa.mod", 1 << 20);
    defer std.testing.allocator.free(mod_text);
    try std.testing.expect(std.mem.containsAtLeast(u8, mod_text, 1, "package \"demo\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mod_text, 1, "require deps/example/shared @HEAD sha256:"));
    try tmp.dir.access(std.testing.io, "sa.sum", .{ .read = true });
    try tmp.dir.access(std.testing.io, "sa_vendor/deps/example/shared/index.sa", .{ .read = true });

    // Listing reads the same declaration back.
    stdout_buf.clearRetainingCapacity();
    const list_argv = [_][]const u8{ "sa", "pkg", "list" };
    const list_code = try saasm.cli.executeWithWriters(std.testing.allocator, list_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), list_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "require deps/example/shared @HEAD sha256:"));

    // Adding the same identity again replaces its line instead of
    // appending a duplicate.
    const readd_code = try saasm.cli.executeWithWriters(std.testing.allocator, add_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), readd_code);
    const mod_text2 = try sio.cwd().readFileAlloc(std.testing.allocator, "sa.mod", 1 << 20);
    defer std.testing.allocator.free(mod_text2);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, mod_text2, "require deps/example/shared"));
}

test "cli cache clean --all removes the project .sla-cache only on request" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, ".sla-cache/macros");
    try writeBytes(tmp.dir, ".sla-cache/macros/probe.idx", "idx");

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const plain_argv = [_][]const u8{ "sa", "cache", "clean" };
    const plain_code = try saasm.cli.executeWithWriters(std.testing.allocator, plain_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), plain_code);
    try tmp.dir.access(std.testing.io, ".sla-cache/macros/probe.idx", .{});

    stdout_buf.clearRetainingCapacity();
    const dry_argv = [_][]const u8{ "sa", "cache", "clean", "--all", "--dry-run" };
    const dry_code = try saasm.cli.executeWithWriters(std.testing.allocator, dry_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), dry_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, ".sla-cache found (dry run, kept)"));
    try tmp.dir.access(std.testing.io, ".sla-cache/macros/probe.idx", .{});

    stdout_buf.clearRetainingCapacity();
    const all_argv = [_][]const u8{ "sa", "cache", "clean", "--all" };
    const all_code = try saasm.cli.executeWithWriters(std.testing.allocator, all_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), all_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, ".sla-cache removed"));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, ".sla-cache/macros/probe.idx", .{}));
}

test "cli help surfaces lifecycle routing, pkg aliases, and plugin confirm" {
    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const help_argv = [_][]const u8{ "sa", "help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "Project lifecycle:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "Pkg alias of `sa pkg install`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "Pkg alias of `sa pkg fetch`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "Pkg alias of `sa pkg audit`"));

    stdout_buf.clearRetainingCapacity();
    const plugin_help_argv = [_][]const u8{ "sa", "plugin", "--help" };
    const plugin_help_code = try saasm.cli.executeWithWriters(std.testing.allocator, plugin_help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), plugin_help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "confirm"));

    stdout_buf.clearRetainingCapacity();
    const cache_help_argv = [_][]const u8{ "sa", "cache", "clean", "--help" };
    const cache_help_code = try saasm.cli.executeWithWriters(std.testing.allocator, cache_help_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), cache_help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "--all"));
}
