//! env / fs helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
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

test "sa_std env helpers are concrete and verifiable" {
    const env_src = try readFileAlloc(std.testing.allocator, "sa_std/env.sa");
    defer std.testing.allocator.free(env_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "@import \"env.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_CURRENT_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_TEMP_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_CURRENT_EXE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_ARGS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_VARS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_SPLIT_PATHS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_SPLIT_PATHS_JSON_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_JOIN_PATHS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_JOIN_PATHS_JSON_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_HAS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_BUFFER_FREE"));

    var env_flat = try flattenFixture(std.testing.allocator, "sa_std/env.sa", env_src);
    defer env_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 11), env_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 9), env_flat.function_sigs.len);
}

test "sa_std env runtime helper is usable from C" {
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
        \\static int has_bytes(const uint8_t *data, uint64_t len, const uint8_t *needle, uint64_t needle_len) {
        \\    uint64_t i = 0;
        \\    if (needle_len == 0) return 1;
        \\    if (len < needle_len) return 0;
        \\    while (i + needle_len <= len) {
        \\        if (memcmp(data + i, needle, needle_len) == 0) return 1;
        \\        i++;
        \\    }
        \\    return 0;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t key[] = "PATH";
        \\    const uint8_t mutation_key[] = "__SA_STD_ENV_C_MUTATION_TEST__";
        \\    const uint8_t mutation_value[] = "sa-env-c-value";
        \\    const uint8_t expected_arg[] = "sa-env-arg-probe";
        \\    const uint8_t expected_env_key[] = "PATH";
        \\    const uint8_t path_list[] = "alpha:beta:gamma";
        \\    const uint8_t expected_path_segment[] = "beta";
        \\    const uint8_t paths_json[] = "[\"alpha\",\"beta\",\"gamma\"]";
        \\    const uint8_t expected_joined[] = "alpha:beta:gamma";
        \\    uint64_t handle = 0;
        \\    uint8_t *data = NULL;
        \\    uint64_t len = 0;
        \\
        \\    handle = sa_env_current_dir();
        \\    if (handle == 0) return 1;
        \\    if (sa_env_buffer_len(handle) == 0) return 11;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 12;
        \\    handle = sa_env_temp_dir();
        \\    if (handle == 0) return 13;
        \\    if (sa_env_buffer_len(handle) == 0) return 14;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 15;
        \\    handle = sa_env_current_exe();
        \\    if (handle == 0) return 16;
        \\    if (sa_env_buffer_len(handle) == 0) return 17;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 18;
        \\    handle = sa_env_args_json();
        \\    if (handle == 0) return 27;
        \\    len = sa_env_buffer_len(handle);
        \\    data = sa_env_buffer_data(handle);
        \\    if (len < 2 || data == NULL || data[0] != '[' || data[len - 1] != ']') return 28;
        \\    if (!has_bytes(data, len, expected_arg, sizeof(expected_arg) - 1)) return 29;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 30;
        \\    handle = sa_env_vars_json();
        \\    if (handle == 0) return 31;
        \\    len = sa_env_buffer_len(handle);
        \\    data = sa_env_buffer_data(handle);
        \\    if (len < 2 || data == NULL || data[0] != '[' || data[len - 1] != ']') return 32;
        \\    if (!has_bytes(data, len, expected_env_key, sizeof(expected_env_key) - 1)) return 33;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 34;
        \\    handle = sa_env_split_paths_json(path_list, sizeof(path_list) - 1);
        \\    if (handle == 0) return 35;
        \\    len = sa_env_buffer_len(handle);
        \\    data = sa_env_buffer_data(handle);
        \\    if (len < 2 || data == NULL || data[0] != '[' || data[len - 1] != ']') return 36;
        \\    if (!has_bytes(data, len, expected_path_segment, sizeof(expected_path_segment) - 1)) return 37;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 38;
        \\    handle = sa_env_join_paths_json(paths_json, sizeof(paths_json) - 1);
        \\    if (handle == 0) return 39;
        \\    len = sa_env_buffer_len(handle);
        \\    data = sa_env_buffer_data(handle);
        \\    if (len != sizeof(expected_joined) - 1 || data == NULL || memcmp(data, expected_joined, sizeof(expected_joined) - 1) != 0) return 40;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 41;
        \\
        \\    if (sa_env_has(key, sizeof(key) - 1) != SA_STD_OK) return 2;
        \\    handle = sa_env_get(key, sizeof(key) - 1);
        \\    if (handle == 0) return 3;
        \\    len = sa_env_buffer_len(handle);
        \\    if (len == 0) return 4;
        \\    data = sa_env_buffer_data(handle);
        \\    if (data == NULL) return 5;
        \\    if (memchr(data, ':', len) == NULL) return 6;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 7;
        \\    if (sa_env_remove_var(mutation_key, sizeof(mutation_key) - 1) != SA_STD_OK) return 19;
        \\    if (sa_env_set_var(mutation_key, sizeof(mutation_key) - 1, mutation_value, sizeof(mutation_value) - 1) != SA_STD_OK) return 20;
        \\    if (sa_env_has(mutation_key, sizeof(mutation_key) - 1) != SA_STD_OK) return 21;
        \\    handle = sa_env_get(mutation_key, sizeof(mutation_key) - 1);
        \\    if (handle == 0) return 22;
        \\    len = sa_env_buffer_len(handle);
        \\    data = sa_env_buffer_data(handle);
        \\    if (len != sizeof(mutation_value) - 1 || data == NULL || memcmp(data, mutation_value, sizeof(mutation_value) - 1) != 0) return 23;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 24;
        \\    if (sa_env_remove_var(mutation_key, sizeof(mutation_key) - 1) != SA_STD_OK) return 25;
        \\    if (sa_env_has(mutation_key, sizeof(mutation_key) - 1) == SA_STD_OK) return 26;
        \\    puts("sa_std env ok");
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
        "sa_std_env_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{ "./sa_std_env_demo", "sa-env-arg-probe" });
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std env ok\n", run_result.stdout);
}

test "sa_std fs helper declarations stay aligned" {
    const fs_iface = try readFileAlloc(std.testing.allocator, "sa_std/fs.sai");
    defer std.testing.allocator.free(fs_iface);
    const fs_src = try readFileAlloc(std.testing.allocator, "sa_std/fs.sa");
    defer std.testing.allocator.free(fs_src);
    const c_header = try readFileAlloc(std.testing.allocator, "src/runtime/sa_std.h");
    defer std.testing.allocator.free(c_header);

    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_open_read(&path: ptr, path_len: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_file_read(file: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_file_seek(file: u64, whence: u32, offset: i64, &out_pos: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_try_exists(&path: ptr, path_len: u64, &out_exists: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_read_file(&path: ptr, path_len: u64, max_bytes: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_read_to_string(&path: ptr, path_len: u64, max_bytes: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_metadata(&path: ptr, path_len: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_file_sync_data(file: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_canonicalize(&path: ptr, path_len: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_read_file_base64(&path: ptr, path_len: u64, max_bytes: u64) -> u64!"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_write_file_base64(&path: ptr, path_len: u64, &data_base64: ptr, data_base64_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_read_dir_json(&path: ptr, path_len: u64, max_entries: u64) -> u64!"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_metadata(&path: ptr, path_len: u64) -> u64!"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_metadata_json(&path: ptr, path_len: u64) -> u64!"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_make_dir(&path: ptr, path_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_create_dir(&path: ptr, path_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_remove_dir_all(&path: ptr, path_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_remove_path(&path: ptr, path_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_copy_file(&from_path: ptr, from_len: u64, &to_path: ptr, to_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_set_permissions(&path: ptr, path_len: u64, mode: u32) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_set_times_ms(&path: ptr, path_len: u64, accessed_ms: i64, modified_ms: i64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_hard_link(&from_path: ptr, from_len: u64, &to_path: ptr, to_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_fs_symlink(&target_path: ptr, target_len: u64, &link_path: ptr, link_len: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_iface, 1, "@extern sa_std_fs_read_link(&path: ptr, path_len: u64, &out_handle: ptr) -> i32"));

    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_OPEN_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SYNC_DATA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SYNC_ALL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_TRY_EXISTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_METADATA_IS_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_READ_DIR_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_CANONICALIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_CREATE_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_REMOVE_DIR_ALL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_COPY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SET_PERMISSIONS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SET_TIMES_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_HARD_LINK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_SYMLINK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, fs_src, 1, "[MACRO] FS_READ_LINK"));

    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_read_file(const uint8_t *path, uint64_t path_len, uint64_t max_bytes, uint64_t *out_handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_read_to_string(const uint8_t *path, uint64_t path_len, uint64_t max_bytes, uint64_t *out_handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_file_sync_data(uint64_t handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_canonicalize(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_set_permissions(const uint8_t *path, uint64_t path_len, uint32_t mode);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_set_times_ms(const uint8_t *path, uint64_t path_len, int64_t accessed_ms, int64_t modified_ms);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_hard_link(const uint8_t *from_path, uint64_t from_len, const uint8_t *to_path, uint64_t to_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_symlink(const uint8_t *target_path, uint64_t target_len, const uint8_t *link_path, uint64_t link_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_read_link(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_file_seek(uint64_t handle, uint32_t whence, int64_t offset, uint64_t *out_pos);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_try_exists(const uint8_t *path, uint64_t path_len, uint8_t *out_exists);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_std_fs_metadata(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_fallible_u64 sa_fs_read_file_base64(const uint8_t *path, uint64_t path_len, uint64_t max_bytes);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_fallible_u64 sa_fs_read_to_string(const uint8_t *path, uint64_t path_len, uint64_t max_bytes);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_write_file_base64(const uint8_t *path, uint64_t path_len, const uint8_t *data_base64, uint64_t data_base64_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_fallible_u64 sa_fs_read_dir_json(const uint8_t *path, uint64_t path_len, uint64_t max_entries);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_fallible_u64 sa_fs_metadata(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_fallible_u64 sa_fs_metadata_json(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_make_dir(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_create_dir(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_remove_dir_all(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_remove_path(const uint8_t *path, uint64_t path_len);"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "int32_t sa_fs_copy_file(const uint8_t *from_path, uint64_t from_len, const uint8_t *to_path, uint64_t to_len);"));
}

test "sa_std fs base64 and directory helpers are usable from C" {
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
        \\    const uint8_t dir[] = "fs_demo_dir/nested";
        \\    const uint8_t root_dir[] = "fs_demo_dir";
        \\    const uint8_t single_dir[] = "fs_single_dir";
        \\    const uint8_t remove_all_dir[] = "fs_remove_all_dir";
        \\    const uint8_t remove_all_nested[] = "fs_remove_all_dir/nested";
        \\    const uint8_t path[] = "fs_demo_dir/nested/hello.txt";
        \\    const uint8_t copy_path[] = "fs_demo_dir/nested/copy.txt";
        \\    const uint8_t encoded[] = "aGVsbG8=";
        \\    sa_std_fallible_u64 read_result = {0};
        \\    sa_std_fallible_u64 string_result = {0};
        \\    sa_std_fallible_u64 dir_result = {0};
        \\    sa_std_fallible_u64 metadata_json_result = {0};
        \\    sa_std_fallible_u64 metadata_result = {0};
        \\    sa_std_fallible_i32 metadata_free_result = {0};
        \\    uint8_t *read_data = NULL;
        \\    uint64_t read_len = 0;
        \\    uint8_t *string_data = NULL;
        \\    uint64_t string_len = 0;
        \\    uint8_t *dir_data = NULL;
        \\    uint64_t dir_len = 0;
        \\    uint8_t *metadata_data = NULL;
        \\    uint64_t metadata_len = 0;
        \\    uint8_t try_exists_value = 255;
        \\
        \\    if (sa_std_fs_try_exists(path, sizeof(path) - 1, &try_exists_value) != SA_STD_OK) return 35;
        \\    if (try_exists_value != 0) return 36;
        \\    if (sa_fs_make_dir(dir, sizeof(dir) - 1) != SA_STD_OK) return 2;
        \\    if (sa_fs_make_dir(dir, sizeof(dir) - 1) != SA_STD_OK) return 12;
        \\    if (sa_fs_create_dir(single_dir, sizeof(single_dir) - 1) != SA_STD_OK) return 26;
        \\    if (sa_fs_create_dir(single_dir, sizeof(single_dir) - 1) == SA_STD_OK) return 27;
        \\    if (sa_fs_remove_dir(single_dir, sizeof(single_dir) - 1) != SA_STD_OK) return 28;
        \\    if (sa_fs_make_dir(remove_all_nested, sizeof(remove_all_nested) - 1) != SA_STD_OK) return 29;
        \\    if (sa_fs_remove_dir(remove_all_dir, sizeof(remove_all_dir) - 1) == SA_STD_OK) return 30;
        \\    if (sa_fs_remove_dir_all(remove_all_dir, sizeof(remove_all_dir) - 1) != SA_STD_OK) return 31;
        \\    if (sa_fs_write_file_base64(path, sizeof(path) - 1, encoded, sizeof(encoded) - 1) != SA_STD_OK) return 3;
        \\    try_exists_value = 0;
        \\    if (sa_std_fs_try_exists(path, sizeof(path) - 1, &try_exists_value) != SA_STD_OK) return 37;
        \\    if (try_exists_value != 1) return 38;
        \\    string_result = sa_fs_read_to_string(path, sizeof(path) - 1, 1024);
        \\    if (string_result.status != SA_STD_OK || string_result.value == 0) return 32;
        \\    string_data = sa_fs_read_buffer_data(string_result.value);
        \\    string_len = sa_fs_read_buffer_len(string_result.value);
        \\    if (string_len != 5 || memcmp(string_data, "hello", 5) != 0) return 33;
        \\    if (sa_fs_read_buffer_free(string_result.value) != SA_STD_OK) return 34;
        \\    read_result = sa_fs_read_file_base64(path, sizeof(path) - 1, 1024);
        \\    if (read_result.status != SA_STD_OK || read_result.value == 0) return 4;
        \\    read_data = sa_fs_read_buffer_data(read_result.value);
        \\    read_len = sa_fs_read_buffer_len(read_result.value);
        \\    if (read_len != sizeof(encoded) - 1 || memcmp(read_data, encoded, sizeof(encoded) - 1) != 0) return 5;
        \\    if (sa_fs_read_buffer_free(read_result.value) != SA_STD_OK) return 6;
        \\
        \\    dir_result = sa_fs_read_dir_json(dir, sizeof(dir) - 1, 32);
        \\    if (dir_result.status != SA_STD_OK || dir_result.value == 0) return 7;
        \\    dir_data = sa_fs_dir_buffer_data(dir_result.value);
        \\    dir_len = sa_fs_dir_buffer_len(dir_result.value);
        \\    if (dir_len == 0) return 8;
        \\    if (memmem(dir_data, dir_len, "hello.txt", 9) == NULL) return 9;
        \\    if (memmem(dir_data, dir_len, "\"isFile\":true", 13) == NULL) return 10;
        \\    if (sa_fs_dir_buffer_free(dir_result.value) != SA_STD_OK) return 11;
        \\
        \\    if (sa_fs_copy_file(path, sizeof(path) - 1, copy_path, sizeof(copy_path) - 1) != SA_STD_OK) return 13;
        \\    if (sa_fs_set_times_ms(copy_path, sizeof(copy_path) - 1, 1700000000000LL, 1700000000000LL) != SA_STD_OK) return 25;
        \\    metadata_json_result = sa_fs_metadata_json(copy_path, sizeof(copy_path) - 1);
        \\    if (metadata_json_result.status != SA_STD_OK || metadata_json_result.value == 0) return 14;
        \\    metadata_data = sa_fs_read_buffer_data(metadata_json_result.value);
        \\    metadata_len = sa_fs_read_buffer_len(metadata_json_result.value);
        \\    if (metadata_len == 0) return 15;
        \\    if (memmem(metadata_data, metadata_len, "\"isFile\":true", 13) == NULL) return 16;
        \\    if (memmem(metadata_data, metadata_len, "\"isDirectory\":false", 19) == NULL) return 17;
        \\    if (sa_fs_read_buffer_free(metadata_json_result.value) != SA_STD_OK) return 18;
        \\
        \\    metadata_result = sa_fs_metadata(copy_path, sizeof(copy_path) - 1);
        \\    if (metadata_result.status != SA_STD_OK || metadata_result.value == 0) return 19;
        \\    if (sa_fs_metadata_is_file(metadata_result.value) != 1) return 20;
        \\    if (sa_fs_metadata_is_directory(metadata_result.value) != 0) return 21;
        \\    metadata_free_result = sa_fs_metadata_free(metadata_result.value);
        \\    if (metadata_free_result.status != SA_STD_OK) return 22;
        \\
        \\    if (sa_fs_remove_path(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 23;
        \\    dir_result = sa_fs_read_dir_json(dir, sizeof(dir) - 1, 32);
        \\    if (dir_result.status == SA_STD_OK) return 24;
        \\    puts("sa_std fs base64 dir metadata copy remove ok");
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
        "sa_std_fs_base64_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_fs_base64_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std fs base64 dir metadata copy remove ok\n", run_result.stdout);
}
