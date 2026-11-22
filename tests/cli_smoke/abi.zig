const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const writeBytes = helpers.writeBytes;
const runCommandAnyExit = helpers.runCommandAnyExit;

test "fallible ABI and ? propagation work end to end" {
    const source =
        \\@helper() -> i32!:
        \\return 7
        \\@main() -> i32!:
        \\tmp = call @helper()
        \\value = ? tmp
        \\return value
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "fallible.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "fallible.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "fallible.sa", "-o", "fallible.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "fallible.out.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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
        .exited => |code| {
            if (code != 0) {
                std.debug.print("fallible u64 ABI probe failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "extern i32 fallible return uses ABI-aligned payload offset" {
    const source =
        \\@extern sa_fs_metadata(&path: ptr, path_len: u64) -> u64!
        \\@extern sa_fs_metadata_free(metadata: u64) -> i32!
        \\@extern sa_test_fallible_i32_value(value: i32) -> i32!
        \\
        \\@const PROBE_PATH = utf8:"probe.env"
        \\
        \\@ffi_wrapper probe_fallible_i32_wire() -> i32:
        \\L_ENTRY:
        \\    sentinel_res = call @sa_test_fallible_i32_value(77)
        \\    sentinel_status = load sentinel_res+0 as i32
        \\    sentinel_value = load sentinel_res+4 as i32
        \\    !sentinel_res
        \\    sentinel_status_ok = eq sentinel_status, 0
        \\    !sentinel_status
        \\    br sentinel_status_ok -> L_CHECK_SENTINEL_VALUE, L_FAIL_SENTINEL_STATUS
        \\
        \\L_CHECK_SENTINEL_VALUE:
        \\    !sentinel_status_ok
        \\    sentinel_value_ok = eq sentinel_value, 77
        \\    !sentinel_value
        \\    br sentinel_value_ok -> L_METADATA, L_FAIL_SENTINEL_VALUE
        \\
        \\L_METADATA:
        \\    !sentinel_value_ok
        \\    path_tmp = *PROBE_PATH
        \\    metadata_res = call @sa_fs_metadata(&path_tmp, 9)
        \\    !path_tmp
        \\    metadata_status = load metadata_res+0 as i32
        \\    metadata = load metadata_res+8 as u64
        \\    !metadata_res
        \\    metadata_ok = eq metadata_status, 0
        \\    !metadata_status
        \\    br metadata_ok -> L_FREE, L_FAIL_METADATA
        \\
        \\L_FREE:
        \\    !metadata_ok
        \\    free_res = call @sa_fs_metadata_free(metadata)
        \\    !metadata
        \\    free_status = load free_res+0 as i32
        \\    free_value = load free_res+4 as i32
        \\    !free_res
        \\    status_ok = eq free_status, 0
        \\    !free_status
        \\    br status_ok -> L_CHECK_VALUE, L_FAIL_STATUS
        \\
        \\L_CHECK_VALUE:
        \\    !status_ok
        \\    value_ok = eq free_value, 0
        \\    !free_value
        \\    br value_ok -> L_TAIL_SENTINEL, L_FAIL_VALUE
        \\
        \\L_TAIL_SENTINEL:
        \\    !value_ok
        \\    tail = alloc 35
        \\    store tail+31, 1 as u8
        \\    resolved = load tail+31 as u8
        \\    !tail
        \\    resolved_ok = eq resolved, 1
        \\    !resolved
        \\    br resolved_ok -> L_PASS, L_FAIL_TAIL
        \\
        \\L_PASS:
        \\    !resolved_ok
        \\    return 0
        \\
        \\L_FAIL_METADATA:
        \\    !metadata_ok
        \\    !metadata
        \\    panic(125)
        \\
        \\L_FAIL_STATUS:
        \\    !status_ok
        \\    !free_value
        \\    panic(126)
        \\
        \\L_FAIL_VALUE:
        \\    !value_ok
        \\    panic(128)
        \\
        \\L_FAIL_TAIL:
        \\    !resolved_ok
        \\    panic(127)
        \\
        \\L_FAIL_SENTINEL_STATUS:
        \\    !sentinel_status_ok
        \\    !sentinel_value
        \\    panic(129)
        \\
        \\L_FAIL_SENTINEL_VALUE:
        \\    !sentinel_value_ok
        \\    panic(130)
        \\
        \\@main() -> i32!:
        \\L_MAIN:
        \\    status = call @probe_fallible_i32_wire()
        \\    return status
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "fallible_i32_file.sa", source);
    try writeBytes(tmp.dir, "probe.env", "PORT=28080\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "fallible_i32_file.sa", "-o", "fallible_i32_file.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible_i32_file.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("fallible i32 ABI probe failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "result unwrap_or and map_or helpers branch on tags correctly" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "const_ptr_store.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "const_ptr_store.sa", "-o", "const_ptr_store.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./const_ptr_store.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
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

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "vtable_indirect.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "vtable_indirect.sa", "-o", "vtable_indirect.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./vtable_indirect.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("OK\n", exe_result.stdout);
}
