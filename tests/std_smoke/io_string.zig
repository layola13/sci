//! io / math / string / path helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const repoRoot = helpers.repoRoot;
const readFileAlloc = helpers.readFileAlloc;
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandWithEnvMap = helpers.runCommandWithEnvMap;
const runCommandAnyExit = helpers.runCommandAnyExit;
const NormalizedInstruction = helpers.NormalizedInstruction;
const normalizeInstruction = helpers.normalizeInstruction;
const expectFlattenEquivalent = helpers.expectFlattenEquivalent;
const dumpInstructionTexts = helpers.dumpInstructionTexts;
const flattenFixture = helpers.flattenFixture;

test "sa_std io helpers are concrete and verifiable" {
    const io_iface = try readFileAlloc(std.testing.allocator, "sa_std/io.sai");
    defer std.testing.allocator.free(io_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_std_println"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_read_line"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_data"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_free"));

    const io_src = try readFileAlloc(std.testing.allocator, "sa_std/io.sa");
    defer std.testing.allocator.free(io_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "@import \"fmt.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] PRINTLN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] READ_LINE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] FORMAT_INT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_CURSOR_READ_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_CURSOR_FILL_BUF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_CURSOR_CONSUME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_CURSOR_WRITE_ALL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_EMPTY_READ_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_REPEAT_READ_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] IO_SINK_WRITE_ALL"));

    var io_flat = try flattenFixture(std.testing.allocator, "sa_std/io.sa", io_src);
    defer io_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), io_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 24), io_flat.function_sigs.len);
}

test "sa_std buffered io helpers are concrete and verifiable" {
    const buf_reader_src = try readFileAlloc(std.testing.allocator, "sa_std/io/buf_reader.sa");
    defer std.testing.allocator.free(buf_reader_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "@import \"../io.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ_LINE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_CLOSE"));

    var buf_reader_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buf_reader.sa", buf_reader_src);
    defer buf_reader_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_reader_flat.function_sigs.len > 0);

    const buf_writer_src = try readFileAlloc(std.testing.allocator, "sa_std/io/buf_writer.sa");
    defer std.testing.allocator.free(buf_writer_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "@import \"../io.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_WRITE_ALL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_FLUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_CLOSE"));

    var buf_writer_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buf_writer.sa", buf_writer_src);
    defer buf_writer_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_writer_flat.function_sigs.len > 0);
}

test "sa_std math helpers are concrete and verifiable" {
    const math_src = try readFileAlloc(std.testing.allocator, "sa_std/math.sa");
    defer std.testing.allocator.free(math_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_ABS_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_MIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_MAX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_CLAMP_U64"));

    var math_flat = try saasm.flattener.flatten(std.testing.allocator, math_src);
    defer math_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), math_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), math_flat.function_sigs.len);
}

test "sa_std string_format helpers are concrete and verifiable" {
    const string_format_src = try readFileAlloc(std.testing.allocator, "sa_std/string_format.sa");
    defer std.testing.allocator.free(string_format_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "@import \"fmt.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_F64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_I64_INTO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_U64_INTO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_F64_INTO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BOOL_INTO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BYTES_INTO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_DATA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_WRITE_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_FREE"));

    var string_format_flat = try flattenFixture(std.testing.allocator, "sa_std/string_format.sa", string_format_src);
    defer string_format_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 14), string_format_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 14), string_format_flat.function_sigs.len);
}

test "sa_std path helpers are concrete and verifiable" {
    const path_src = try readFileAlloc(std.testing.allocator, "sa_std/path.sa");
    defer std.testing.allocator.free(path_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"core/slice.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"string.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_BASENAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_DIRNAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_STEM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_EXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_IS_ABSOLUTE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_HAS_ROOT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_IS_RELATIVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_STARTS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_TRY_STRIP_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_ENDS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_JOIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_PARENT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_FILE_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_FILE_STEM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_EXTENSION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_WITH_FILE_NAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_ANCESTOR_COUNT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_TRY_ANCESTOR_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_TRY_EXISTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_METADATA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_CANONICALIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_READ_LINK"));

    var path_flat = try flattenFixture(std.testing.allocator, "sa_std/path.sa", path_src);
    defer path_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), path_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), path_flat.function_sigs.len);
}

test "sa_std path module exercises real string macros" {
    const path_src = try readFileAlloc(std.testing.allocator, "sa_std/path.sa");
    defer std.testing.allocator.free(path_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_BASENAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_DIRNAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_STEM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_EXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_JOIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "EXPAND STR_CONCAT"));

    var path_flat = try flattenFixture(std.testing.allocator, "sa_std/path.sa", path_src);
    defer path_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), path_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), path_flat.function_sigs.len);
}

test "sa_std string concat runtime helper is usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *left = (const uint8_t *)"hello, ";
        \\    const uint8_t *right = (const uint8_t *)"world";
        \\    uint64_t handle = sa_string_concat(left, 7, right, 5);
        \\    uint64_t len = 0;
        \\    uint8_t *bytes = NULL;
        \\    if (handle == 0) return 2;
        \\    len = sa_fmt_buffer_len(handle);
        \\    if (len != 12) return 3;
        \\    bytes = sa_fmt_buffer_data(handle);
        \\    if (bytes == NULL) return 4;
        \\    if (memcmp(bytes, "hello, world", 12) != 0) return 5;
        \\    if (sa_fmt_buffer_free(handle) != SA_STD_OK) return 6;
        \\    puts("sa_std string concat ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_string_concat_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_string_concat_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std string concat ok\n", run_result.stdout);
}

test "sa_std no-alloc format helpers write into caller buffers" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    uint8_t buf[32] = {0};
        \\    uint64_t len = 0;
        \\    if (sa_fmt_i64_into(-42, 10, buf, sizeof(buf), &len) != SA_STD_OK) return 2;
        \\    if (len != 3 || memcmp(buf, "-42", 3) != 0) return 3;
        \\    memset(buf, 0, sizeof(buf));
        \\    if (sa_fmt_u64_into(255, 16, buf, sizeof(buf), &len) != SA_STD_OK) return 4;
        \\    if (len != 2 || memcmp(buf, "ff", 2) != 0) return 5;
        \\    memset(buf, 0, sizeof(buf));
        \\    if (sa_fmt_bool_into(1, buf, sizeof(buf), &len) != SA_STD_OK) return 6;
        \\    if (len != 4 || memcmp(buf, "true", 4) != 0) return 7;
        \\    memset(buf, 0, sizeof(buf));
        \\    if (sa_fmt_bytes_into((const uint8_t *)"abc", 3, buf, sizeof(buf), &len) != SA_STD_OK) return 8;
        \\    if (len != 3 || memcmp(buf, "abc", 3) != 0) return 9;
        \\    if (sa_fmt_i64_into(12345, 10, buf, 2, &len) != SA_STD_ERR_TRUNCATED) return 10;
        \\    if (len != 5) return 11;
        \\    puts("sa_std fmt into ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_fmt_into_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_fmt_into_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std fmt into ok\n", run_result.stdout);
}
