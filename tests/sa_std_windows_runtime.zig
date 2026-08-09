const std = @import("std");
const build_options = @import("build_options");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn expectSuccess(result: std.process.Child.RunResult) !void {
    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                if (result.stdout.len != 0) std.debug.print("stdout:\n{s}", .{result.stdout});
                if (result.stderr.len != 0) std.debug.print("stderr:\n{s}", .{result.stderr});
                std.debug.print("exit code: {d}\n", .{code});
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "windows sa_std bootstrap print and file IO link from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <string.h>
        \\
        \\static int expect_buffer(uint64_t handle, const char *needle) {
        \\    uint8_t *ptr = sa_env_buffer_data(handle);
        \\    uint64_t len = sa_env_buffer_len(handle);
        \\    if (handle == 0 || ptr == 0 || len == 0) return 0;
        \\    if (needle != 0 && strstr((const char *)ptr, needle) == 0) return 0;
        \\    return sa_env_buffer_free(handle) == SA_STD_OK;
        \\}
        \\
        \\static int expect_fmt_buffer(uint64_t handle, const char *expected) {
        \\    uint8_t *ptr = sa_fmt_buffer_data(handle);
        \\    uint64_t len = sa_fmt_buffer_len(handle);
        \\    uint64_t expected_len = (uint64_t)strlen(expected);
        \\    if (handle == 0 || ptr == 0 || len != expected_len) return 0;
        \\    if (memcmp(ptr, expected, expected_len) != 0) return 0;
        \\    return sa_fmt_buffer_free(handle) == SA_STD_OK;
        \\}
        \\
        \\static int is_lower_hex(uint8_t c) {
        \\    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        \\}
        \\
        \\static int check_uuid(uint64_t handle, uint8_t out[36]) {
        \\    uint8_t *ptr = sa_env_buffer_data(handle);
        \\    uint64_t len = sa_env_buffer_len(handle);
        \\    uint64_t i = 0;
        \\    if (handle == 0 || ptr == 0 || len != 36) return 0;
        \\    for (i = 0; i < len; ++i) {
        \\        if (i == 8 || i == 13 || i == 18 || i == 23) {
        \\            if (ptr[i] != '-') return 0;
        \\        } else if (!is_lower_hex(ptr[i])) {
        \\            return 0;
        \\        }
        \\    }
        \\    if (ptr[14] != '4') return 0;
        \\    if (ptr[19] != '8' && ptr[19] != '9' && ptr[19] != 'a' && ptr[19] != 'b') return 0;
        \\    memcpy(out, ptr, 36);
        \\    return sa_env_buffer_free(handle) == SA_STD_OK;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t msg[] = "sa_std windows ok";
        \\    const uint8_t path[] = "sa_std_windows_io.txt";
        \\    const uint8_t renamed_path[] = "sa_std_windows_renamed.txt";
        \\    const uint8_t copied_path[] = "sa_std_windows_copied.txt";
        \\    const uint8_t base64_path[] = "sa_std_windows_base64.txt";
        \\    const uint8_t handle_io_path[] = "sa_std_windows_handle_io.txt";
        \\    const uint8_t handle_payload[] = "abcdef";
        \\    const uint8_t hard_link_path[] = "sa_std_windows_hard_link.txt";
        \\    const uint8_t nested_dir[] = "sa_std_windows_dir\\\\nested";
        \\    const uint8_t leaf_dir[] = "sa_std_windows_dir\\\\leaf";
        \\    const uint8_t root_dir[] = "sa_std_windows_dir";
        \\    const uint8_t payload[] = "payload";
        \\    const uint8_t env_key[] = "SA_STD_WINDOWS_BOOTSTRAP_SMOKE";
        \\    const uint8_t env_value[] = "env-payload";
        \\    const uint8_t path_list[] = "C:\\\\one;D:\\\\two";
        \\    const uint8_t path_json[] = "[\"C:\\\\\\\\one\",\"D:\\\\\\\\two\"]";
        \\    const uint8_t utf8_text[] = "A\xC3\xA9";
        \\    const uint8_t invalid_utf8[] = { 0xff };
        \\    const uint8_t invalid_base64[] = "%%%";
        \\    const uint8_t trim_text[] = " \ttrim\r\n";
        \\    SaTimeDate now = {0};
        \\    uint64_t handle = 0;
        \\    uint8_t *data = 0;
        \\    uint64_t len = 0;
        \\    uint64_t codepoint = 0;
        \\    uint64_t start = 0;
        \\    uint64_t t0 = 0;
        \\    uint64_t t1 = 0;
        \\    uint8_t exists = 0;
        \\    uint8_t thread_result = 1;
        \\    uint64_t raw_thread = 1;
        \\    uint8_t uuid_a[36] = {0};
        \\    uint8_t uuid_b[36] = {0};
        \\    uint8_t fmt_out[32] = {0};
        \\    const SaProcessArgv process_args[] = {
        \\        { (const uint8_t *)"cmd.exe", 7 },
        \\        { (const uint8_t *)"/d", 2 },
        \\        { (const uint8_t *)"/c", 2 },
        \\        { (const uint8_t *)"process_fixture.cmd", 19 },
        \\    };
        \\    const SaProcessArgv exit_args[] = {
        \\        { (const uint8_t *)"cmd.exe", 7 },
        \\        { (const uint8_t *)"/d", 2 },
        \\        { (const uint8_t *)"/c", 2 },
        \\        { (const uint8_t *)"exit /b 0", 9 },
        \\    };
        \\    const SaProcessArgv wait_args[] = {
        \\        { (const uint8_t *)"cmd.exe", 7 },
        \\        { (const uint8_t *)"/d", 2 },
        \\        { (const uint8_t *)"/c", 2 },
        \\        { (const uint8_t *)"wait_fixture.cmd", 16 },
        \\    };
        \\    const SaProcessArgv cwd_args[] = {
        \\        { (const uint8_t *)"cmd.exe", 7 },
        \\        { (const uint8_t *)"/d", 2 },
        \\        { (const uint8_t *)"/c", 2 },
        \\        { (const uint8_t *)"cwd_fixture.cmd", 15 },
        \\    };
        \\    const uint8_t process_cwd[] = "process_cwd";
        \\    uint64_t process = 0;
        \\    uint64_t stdout_handle = 0;
        \\    uint64_t stderr_handle = 0;
        \\    uint32_t child_pid = 0;
        \\    uint32_t exit_code = 0;
        \\    int32_t ready = 0;
        \\    int32_t raw_status = 1;
        \\    uint8_t process_out[64] = {0};
        \\    uint8_t process_err[64] = {0};
        \\    const uint8_t json_doc[] = "{\"name\":\"sci\",\"active\":true,\"count\":7,\"ratio\":1.5,\"items\":[1,2]}";
        \\    uint64_t json_root = 0;
        \\    uint64_t json_child = 0;
        \\    uint64_t json_item = 0;
        \\    uint64_t json_buffer = 0;
        \\    const uint8_t *json_ptr = 0;
        \\    uint64_t json_len = 0;
        \\    int64_t json_i64 = 0;
        \\    double json_f64 = 0.0;
        \\    uint8_t json_bool = 0;
        \\    uint64_t json_writer = 0;
        \\    uint64_t json_written_root = 0;
        \\    uint64_t json_scanner = 0;
        \\    uint64_t json_stream = 0;
        \\    uint64_t file_handle = 0;
        \\    uint64_t io_count = 99;
        \\    uint64_t io_pos = 99;
        \\    uint8_t io_data[16] = {0};
        \\    sa_std_fallible_u64 metadata_result = {0};
        \\    sa_std_fallible_u64 metadata_json_result = {0};
        \\    sa_std_fallible_i32 metadata_free_result = {0};
        \\    sa_std_fallible_u64 dir_result = {0};
        \\    uint64_t dir_entry = 0;
        \\    const uint8_t *dir_name = 0;
        \\    SaJsonToken json_token = {0};
        \\    const uint8_t json_chunk1[] = "{\"name\":\"s";
        \\    const uint8_t json_chunk2[] = "ci\",\"count\":";
        \\    const uint8_t json_chunk3[] = "7}";
        \\
        \\    if (sa_std_version() != SA_STD_ABI_VERSION) return 2;
        \\    if (sa_std_println(msg, sizeof(msg) - 1) != SA_STD_OK) return 3;
        \\    sa_print_bytes((const uint8_t *)"", 0);
        \\    if (sa_fs_write_file(path, sizeof(path) - 1, payload, sizeof(payload) - 1) != SA_STD_OK) return 4;
        \\    if (sa_std_fs_read_file(path, sizeof(path) - 1, 1024, &handle) != SA_STD_OK) return 5;
        \\    if (handle == 0) return 6;
        \\    data = sa_fs_read_buffer_data(handle);
        \\    len = sa_fs_read_buffer_len(handle);
        \\    if (data == 0 || len != sizeof(payload) - 1) return 7;
        \\    if (memcmp(data, payload, sizeof(payload) - 1) != 0) return 8;
        \\    if (sa_fs_read_buffer_free(handle) != SA_STD_OK) return 9;
        \\    if (sa_std_fs_exists(path, sizeof(path) - 1) != SA_STD_OK) return 76;
        \\    if (sa_std_fs_try_exists(path, sizeof(path) - 1, &exists) != SA_STD_OK || exists != 1) return 77;
        \\    if (sa_std_fs_len(path, sizeof(path) - 1, &len) != SA_STD_OK || len != sizeof(payload) - 1) return 78;
        \\    if (sa_std_fs_read_to_string(path, sizeof(path) - 1, 1024, &handle) != SA_STD_OK) return 79;
        \\    data = sa_fs_read_buffer_data(handle);
        \\    len = sa_fs_read_buffer_len(handle);
        \\    if (data == 0 || len != sizeof(payload) - 1 || memcmp(data, payload, len) != 0) return 80;
        \\    if (sa_fs_read_buffer_free(handle) != SA_STD_OK) return 81;
        \\    if (sa_fs_rename(path, sizeof(path) - 1, renamed_path, sizeof(renamed_path) - 1) != SA_STD_OK) return 82;
        \\    exists = 1;
        \\    if (sa_std_fs_try_exists(path, sizeof(path) - 1, &exists) != SA_STD_OK || exists != 0) return 83;
        \\    if (sa_fs_copy_file(renamed_path, sizeof(renamed_path) - 1, copied_path, sizeof(copied_path) - 1) != SA_STD_OK) return 84;
        \\    handle = 42;
        \\    if (sa_std_fs_canonicalize(copied_path, sizeof(copied_path) - 1, &handle) != SA_STD_OK || handle == 0) return 114;
        \\    data = sa_fs_read_buffer_data(handle);
        \\    len = sa_fs_read_buffer_len(handle);
        \\    if (data == 0 || len <= sizeof(copied_path) - 1) return 115;
        \\    if (memcmp(data + len - (sizeof(copied_path) - 1), copied_path, sizeof(copied_path) - 1) != 0) return 116;
        \\    if (sa_fs_read_buffer_free(handle) != SA_STD_OK) return 117;
        \\    handle = 42;
        \\    if (sa_std_fs_canonicalize((const uint8_t *)"missing-path", 12, &handle) != SA_STD_ERR_NOT_FOUND || handle != 0) return 118;
        \\    if (sa_std_fs_canonicalize(copied_path, sizeof(copied_path) - 1, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 119;
        \\    handle = 42;
        \\    if (sa_std_fs_read_link((const uint8_t *)"missing-link", 12, &handle) != SA_STD_ERR_NOT_FOUND || handle != 0) return 120;
        \\    if (sa_std_fs_read_link(copied_path, sizeof(copied_path) - 1, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 121;
        \\    if (sa_fs_make_dir(nested_dir, sizeof(nested_dir) - 1) != SA_STD_OK) return 85;
        \\    if (sa_fs_create_dir(leaf_dir, sizeof(leaf_dir) - 1) != SA_STD_OK) return 86;
        \\    if (sa_fs_remove_dir(leaf_dir, sizeof(leaf_dir) - 1) != SA_STD_OK) return 87;
        \\    if (sa_fs_remove_path(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 88;
        \\    if (sa_std_fs_remove(copied_path, sizeof(copied_path) - 1) != SA_STD_OK) return 89;
        \\    if (sa_fs_remove_file(renamed_path, sizeof(renamed_path) - 1) != SA_STD_OK) return 90;
        \\    if (sa_std_fs_exists(renamed_path, sizeof(renamed_path) - 1) != SA_STD_ERR_NOT_FOUND) return 91;
        \\    if (sa_std_fs_try_exists(path, sizeof(path) - 1, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 92;
        \\    if (sa_std_fs_len(path, sizeof(path) - 1, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 93;
        \\    if (sa_fs_write_file_base64(base64_path, sizeof(base64_path) - 1, (const uint8_t *)"aGVsbG8=", 8) != SA_STD_OK) return 99;
        \\    if (sa_std_fs_read_file_base64(base64_path, sizeof(base64_path) - 1, 1024, &handle) != SA_STD_OK) return 100;
        \\    if (!expect_fmt_buffer(handle, "aGVsbG8=")) return 101;
        \\    if (sa_fs_write_file_base64(base64_path, sizeof(base64_path) - 1, (const uint8_t *)"%%%", 3) != SA_STD_ERR_INVALID_ARGUMENT) return 102;
        \\    if (sa_fs_remove_file(base64_path, sizeof(base64_path) - 1) != SA_STD_OK) return 103;
        \\    if (sa_deno_env_set(env_key, sizeof(env_key) - 1, env_value, sizeof(env_value) - 1) != SA_STD_OK) return 10;
        \\    if (sa_env_has(env_key, sizeof(env_key) - 1) != SA_STD_OK) return 57;
        \\    handle = sa_env_get(env_key, sizeof(env_key) - 1);
        \\    data = sa_env_buffer_data(handle);
        \\    len = sa_env_buffer_len(handle);
        \\    if (data == 0 || len != sizeof(env_value) - 1) return 11;
        \\    if (memcmp(data, env_value, sizeof(env_value) - 1) != 0) return 12;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 13;
        \\    if (sa_deno_env_delete(env_key, sizeof(env_key) - 1) != SA_STD_OK) return 14;
        \\    if (sa_env_has(env_key, sizeof(env_key) - 1) != SA_STD_ERR_NOT_FOUND) return 58;
        \\    if (sa_env_get(env_key, sizeof(env_key) - 1) != 0) return 15;
        \\    if (!expect_buffer(sa_deno_cwd(), 0)) return 16;
        \\    if (!expect_buffer(sa_env_current_dir(), 0)) return 17;
        \\    if (!expect_buffer(sa_env_current_exe(), "sa_std_windows_smoke")) return 18;
        \\    if (!expect_buffer(sa_env_temp_dir(), 0)) return 59;
        \\    if (!expect_buffer(sa_env_home_dir(), 0)) return 60;
        \\    if (!expect_buffer(sa_env_args_json(), "sa_std_windows_smoke")) return 61;
        \\    if (!expect_buffer(sa_deno_args_json(), 0)) return 62;
        \\    if (!expect_buffer(sa_env_vars_json(), "PATH")) return 63;
        \\    if (!expect_fmt_buffer(sa_env_split_paths_json(path_list, sizeof(path_list) - 1), "[\"C:\\\\\\\\one\",\"D:\\\\\\\\two\"]")) return 64;
        \\    if (!expect_fmt_buffer(sa_env_join_paths_json(path_json, sizeof(path_json) - 1), "C:\\\\one;D:\\\\two")) return 65;
        \\    if (!expect_buffer(sa_deno_version_json(), "sa-std")) return 19;
        \\    if (!expect_buffer(sa_deno_version_deno(), "sa-std")) return 20;
        \\    if (!expect_buffer(sa_deno_build_json(), "windows")) return 21;
        \\    if (!expect_buffer(sa_deno_build_os(), "windows")) return 22;
        \\    if (!expect_buffer(sa_deno_build_platform_family(), "windows")) return 23;
        \\    if (!expect_buffer(sa_deno_date_now_iso(), "Z")) return 66;
        \\    if (!check_uuid(sa_deno_random_uuid(), uuid_a)) return 111;
        \\    if (!check_uuid(sa_deno_random_uuid(), uuid_b)) return 112;
        \\    if (memcmp(uuid_a, uuid_b, sizeof(uuid_a)) == 0) return 113;
        \\    if (!expect_fmt_buffer(sa_deno_btoa((const uint8_t *)"hello", 5), "aGVsbG8=")) return 94;
        \\    if (!expect_fmt_buffer(sa_deno_atob((const uint8_t *)"aGVsbG8=", 8), "hello")) return 95;
        \\    if (sa_deno_atob(invalid_base64, sizeof(invalid_base64) - 1) != 0) return 96;
        \\    if (!expect_fmt_buffer(sa_deno_text_encode(utf8_text, sizeof(utf8_text) - 1), "A\xC3\xA9")) return 97;
        \\    if (!expect_fmt_buffer(sa_deno_text_decode(utf8_text, sizeof(utf8_text) - 1), "A\xC3\xA9")) return 98;
        \\    if (!expect_fmt_buffer(sa_fmt_i64(-42, 10), "-42")) return 24;
        \\    if (!expect_fmt_buffer(sa_fmt_u64(255, 16), "ff")) return 25;
        \\    if (!expect_fmt_buffer(sa_fmt_u64(255, 17), "FF")) return 26;
        \\    if (!expect_fmt_buffer(sa_fmt_bool(1), "true")) return 27;
        \\    if (!expect_fmt_buffer(sa_fmt_bytes((const uint8_t *)"abc", 3), "abc")) return 28;
        \\    if (sa_fmt_i64_into(-7, 10, fmt_out, sizeof(fmt_out), &len) != SA_STD_OK) return 29;
        \\    if (len != 2 || memcmp(fmt_out, "-7", 2) != 0) return 30;
        \\    if (sa_fmt_u64_into(10, 2, fmt_out, sizeof(fmt_out), &len) != SA_STD_OK) return 31;
        \\    if (len != 4 || memcmp(fmt_out, "1010", 4) != 0) return 32;
        \\    if (sa_fmt_bool_into(0, fmt_out, sizeof(fmt_out), &len) != SA_STD_OK) return 33;
        \\    if (len != 5 || memcmp(fmt_out, "false", 5) != 0) return 34;
        \\    if (sa_fmt_bytes_into((const uint8_t *)"xyz", 3, fmt_out, sizeof(fmt_out), &len) != SA_STD_OK) return 35;
        \\    if (len != 3 || memcmp(fmt_out, "xyz", 3) != 0) return 36;
        \\    if (sa_fmt_i64_into(12345, 10, fmt_out, 2, &len) != SA_STD_ERR_TRUNCATED) return 37;
        \\    if (len != 5) return 38;
        \\    if (!expect_fmt_buffer(sa_string_concat((const uint8_t *)"ab", 2, (const uint8_t *)"cd", 2), "abcd")) return 39;
        \\    if (sa_str_is_ascii((const uint8_t *)"abc", 3) != 1) return 40;
        \\    if (sa_str_is_ascii(utf8_text, sizeof(utf8_text) - 1) != 0) return 41;
        \\    if (sa_str_eq_ignore_ascii_case((const uint8_t *)"Sa", 2, (const uint8_t *)"sA", 2) != 1) return 42;
        \\    if (sa_str_eq_ignore_ascii_case((const uint8_t *)"Sa", 2, (const uint8_t *)"sb", 2) != 0) return 43;
        \\    if (sa_str_trim_ascii_start_index(trim_text, sizeof(trim_text) - 1) != 2) return 44;
        \\    if (sa_str_trim_ascii_end_len(trim_text, sizeof(trim_text) - 1) != 6) return 45;
        \\    if (sa_str_utf8_validate(utf8_text, sizeof(utf8_text) - 1) != SA_STD_OK) return 46;
        \\    if (sa_str_utf8_validate(invalid_utf8, sizeof(invalid_utf8)) != SA_STD_ERR_INVALID_ARGUMENT) return 47;
        \\    if (sa_str_utf8_char_count(utf8_text, sizeof(utf8_text) - 1) != 2) return 48;
        \\    if (sa_str_utf8_char_at(utf8_text, sizeof(utf8_text) - 1, 1, &codepoint) != SA_STD_OK) return 49;
        \\    if (codepoint != 233) return 50;
        \\    if (sa_str_utf8_char_at_byte(utf8_text, sizeof(utf8_text) - 1, 1, &codepoint, &len) != SA_STD_OK) return 51;
        \\    if (codepoint != 233 || len != 2) return 52;
        \\    if (sa_str_utf8_lossy_next(invalid_utf8, sizeof(invalid_utf8), 0, &codepoint, &len) != SA_STD_OK) return 53;
        \\    if (codepoint != 65533 || len != 1) return 54;
        \\    if (sa_str_utf8_char_range_at(utf8_text, sizeof(utf8_text) - 1, 1, &start, &len) != SA_STD_OK) return 55;
        \\    if (start != 1 || len != 2) return 56;
        \\    t0 = sa_time_instant_ns();
        \\    if (sa_time_sleep_ms(0) != SA_STD_OK) return 67;
        \\    if (sa_time_sleep_ns(0) != SA_STD_OK) return 68;
        \\    t1 = sa_time_instant_ns();
        \\    if (t1 < t0) return 69;
        \\    if (sa_time_unix_s() <= 0) return 70;
        \\    if (sa_time_unix_ms() <= 0) return 71;
        \\    if (sa_time_unix_ns() <= 0) return 72;
        \\    if (sa_time_utc_now(&now) != SA_STD_OK) return 73;
        \\    if (now.year < 2024 || now.month < 1 || now.month > 12 || now.day < 1 || now.day > 31) return 74;
        \\    if (sa_time_utc_now(0) != SA_STD_ERR_INVALID_ARGUMENT) return 75;
        \\    if (sa_thread_current_id() == 0) return 104;
        \\    if (sa_thread_yield_now() != SA_STD_OK) return 105;
\\    if (sa_thread_as_pthread_t(0, &raw_thread) != SA_STD_ERR_INVALID_HANDLE || raw_thread != 0) return 106;
        \\    raw_thread = 1;
\\    if (sa_thread_into_pthread_t(0, &raw_thread) != SA_STD_ERR_INVALID_HANDLE || raw_thread != 0) return 107;
\\    if (sa_thread_raw_pthread_join(0, &thread_result) != SA_STD_ERR_INVALID_HANDLE || thread_result != 0) return 108;
        \\    if (sa_thread_as_pthread_t(0, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 109;
        \\    if (sa_thread_raw_pthread_join(0, 0) != SA_STD_ERR_INVALID_ARGUMENT) return 110;
        \\    if (sa_std_process_id() == 0) return 126;
        \\    if (sa_std_process_run(process_args, 4, &process) != SA_STD_OK || process == 0) return 127;
        \\    if (sa_std_process_child_id(process, &child_pid) != SA_STD_OK || child_pid == 0) return 128;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 7) return 129;
        \\    if (sa_std_process_try_wait(process, &ready, &exit_code) != SA_STD_OK || ready != 1 || exit_code != 7) return 130;
        \\    if (sa_std_process_read_stdout(process, process_out, sizeof(process_out), &len) != SA_STD_OK) return 131;
        \\    if (len != 13 || memcmp(process_out, "process-out\r\n", 13) != 0) return 132;
        \\    if (sa_std_process_read_stdout(process, process_out, sizeof(process_out), &len) != SA_STD_OK || len != 0) return 133;
        \\    if (sa_std_process_read_stderr(process, process_err, sizeof(process_err), &len) != SA_STD_OK) return 134;
        \\    if (len != 13 || memcmp(process_err, "process-err\r\n", 13) != 0) return 135;
        \\    if (sa_std_process_wait_raw(process, &raw_status) != SA_STD_ERR_UNSUPPORTED || raw_status != 1) return 136;
        \\    handle = 42;
        \\    if (sa_std_process_pidfd(process, &handle) != SA_STD_ERR_UNSUPPORTED || handle != 0) return 137;
        \\    if (sa_std_process_send_signal(process, 15) != SA_STD_ERR_UNSUPPORTED) return 138;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 139;
        \\    if (sa_std_process_close(process) != SA_STD_ERR_INVALID_HANDLE) return 140;
        \\    if (sa_std_process_spawn(exit_args, 4, &process) != SA_STD_OK) return 141;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 0) return 142;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 143;
        \\    if (sa_std_process_spawn_stream(process_args, 4, &process, &stdout_handle, &stderr_handle) != SA_STD_OK) return 144;
        \\    if (sa_std_read(stdout_handle, process_out, sizeof(process_out), &len) != SA_STD_OK || len != 13) return 145;
        \\    if (memcmp(process_out, "process-out\r\n", 13) != 0) return 146;
        \\    if (sa_io_read(stderr_handle, process_err, sizeof(process_err), &len) != SA_STD_OK || len != 13) return 147;
        \\    if (memcmp(process_err, "process-err\r\n", 13) != 0) return 148;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 7) return 149;
        \\    if (sa_std_close(stdout_handle) != SA_STD_OK || sa_io_close(stderr_handle) != SA_STD_OK) return 150;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 151;
        \\    if (sa_std_process_exec_capture(process_args, 4, &exit_code, &stdout_handle, &stderr_handle) != SA_STD_OK) return 152;
        \\    if (exit_code != 7 || !expect_fmt_buffer(stdout_handle, "process-out\r\n")) return 153;
        \\    if (!expect_fmt_buffer(stderr_handle, "process-err\r\n")) return 154;
        \\    process = 42;
        \\    if (sa_std_process_run(0, 0, &process) != SA_STD_ERR_INVALID_ARGUMENT || process != 0) return 155;
        \\    if (sa_std_process_spawn_stream(process_args, 4, 0, &stdout_handle, &stderr_handle) != SA_STD_ERR_INVALID_ARGUMENT) return 156;
        \\    if (sa_std_process_spawn(wait_args, 4, &process) != SA_STD_OK) return 157;
        \\    ready = 1;
        \\    exit_code = 99;
        \\    if (sa_std_process_try_wait(process, &ready, &exit_code) != SA_STD_OK || ready != 0 || exit_code != 0) return 158;
        \\    if (sa_std_process_kill(process) != SA_STD_OK) return 159;
        \\    ready = 0;
        \\    if (sa_std_process_try_wait(process, &ready, &exit_code) != SA_STD_OK || ready != 1) return 160;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 161;
        \\    if (sa_std_process_run_cwd(cwd_args, 4, process_cwd, sizeof(process_cwd) - 1, &process) != SA_STD_OK) return 162;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 0) return 163;
        \\    if (sa_std_process_read_stdout(process, process_out, sizeof(process_out), &len) != SA_STD_OK || len != 8) return 164;
        \\    if (memcmp(process_out, "cwd-ok\r\n", 8) != 0 || sa_std_process_close(process) != SA_STD_OK) return 165;
        \\    if (sa_std_process_run_command_ext(cwd_args, 4, process_cwd, sizeof(process_cwd) - 1, 1, 0, 0, 0, 0, 0, 0, &process) != SA_STD_OK) return 166;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 0 || sa_std_process_close(process) != SA_STD_OK) return 167;
        \\    if (sa_std_process_spawn_stream_cwd(cwd_args, 4, process_cwd, sizeof(process_cwd) - 1, &process, &stdout_handle, &stderr_handle) != SA_STD_OK) return 168;
        \\    if (sa_std_read(stdout_handle, process_out, sizeof(process_out), &len) != SA_STD_OK || len != 8 || memcmp(process_out, "cwd-ok\r\n", 8) != 0) return 169;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || sa_std_close(stdout_handle) != SA_STD_OK || sa_std_close(stderr_handle) != SA_STD_OK || sa_std_process_close(process) != SA_STD_OK) return 170;
        \\    if (sa_std_process_exec_capture_cwd(cwd_args, 4, process_cwd, sizeof(process_cwd) - 1, &exit_code, &stdout_handle, &stderr_handle) != SA_STD_OK) return 171;
        \\    if (exit_code != 0 || !expect_fmt_buffer(stdout_handle, "cwd-ok\r\n") || !expect_fmt_buffer(stderr_handle, "")) return 172;
        \\    if (sa_std_process_run_command_ext(exit_args, 4, 0, 0, 0, (const uint8_t *)"custom", 6, 1, 0, 0, 0, &process) != SA_STD_OK) return 173;
        \\    if (sa_std_process_wait(process, &exit_code) != SA_STD_OK || exit_code != 0 || sa_std_process_close(process) != SA_STD_OK) return 174;
        \\    process = 42;
        \\    if (sa_std_process_spawn_command_ext(cwd_args, 4, 0, 0, 0, 0, 0, 0, 1, 1, 0, &process) != SA_STD_ERR_UNSUPPORTED || process != 0) return 175;
        \\    process = stdout_handle = stderr_handle = 42;
        \\    if (sa_std_process_spawn_stream_command_ext(cwd_args, 4, 0, 0, 0, 0, 0, 0, 0, 0, 1, &process, &stdout_handle, &stderr_handle) != SA_STD_ERR_UNSUPPORTED) return 176;
        \\    if (process != 0 || stdout_handle != 0 || stderr_handle != 0) return 177;
        \\    json_root = sa_json_parse(json_doc, sizeof(json_doc) - 1);
        \\    if (json_root == 0 || sa_json_kind(json_root) != SA_JSON_KIND_OBJECT) return 177;
        \\    if (sa_json_value_count(json_root, &len) != SA_STD_OK || len != 5) return 178;
        \\    if (sa_json_object_get_string(json_root, (const uint8_t *)"name", 4, &json_ptr, &json_len) != SA_STD_OK) return 179;
        \\    if (json_ptr == 0 || json_len != 3 || memcmp(json_ptr, "sci", 3) != 0) return 180;
        \\    if (sa_json_object_get_bool(json_root, (const uint8_t *)"active", 6, &json_bool) != SA_STD_OK || json_bool != 1) return 181;
        \\    if (sa_json_object_get_i64(json_root, (const uint8_t *)"count", 5, &json_i64) != SA_STD_OK || json_i64 != 7) return 182;
        \\    if (sa_json_object_get_f64(json_root, (const uint8_t *)"ratio", 5, &json_f64) != SA_STD_OK || json_f64 != 1.5) return 183;
        \\    if (sa_json_object_key_at(json_root, 0, &json_ptr, &json_len) != SA_STD_OK || json_ptr == 0 || json_len == 0) return 184;
        \\    if (sa_json_object_get(json_root, (const uint8_t *)"items", 5, &json_child) != SA_STD_OK) return 185;
        \\    if (sa_json_kind(json_child) != SA_JSON_KIND_ARRAY || sa_json_value_count(json_child, &len) != SA_STD_OK || len != 2) return 186;
        \\    if (sa_json_array_get(json_child, 1, &json_item) != SA_STD_OK || sa_json_as_i64(json_item, &json_i64) != SA_STD_OK || json_i64 != 2) return 187;
        \\    if (sa_json_stringify(json_root, &json_buffer) != SA_STD_OK || json_buffer == 0) return 188;
        \\    json_ptr = sa_json_buffer_data(json_buffer);
        \\    json_len = sa_json_buffer_len(json_buffer);
        \\    if (json_ptr == 0 || json_len < 12 || memcmp(json_ptr, "{\"name\":\"sci", 12) != 0) return 189;
        \\    if (sa_json_buffer_free(json_buffer) != SA_STD_OK) return 190;
        \\    if (sa_json_free(json_root) != SA_STD_OK) return 191;
        \\    if (sa_json_as_i64(json_item, &json_i64) != SA_STD_OK || json_i64 != 2) return 192;
        \\    if (sa_json_free(json_item) != SA_STD_OK || sa_json_free(json_child) != SA_STD_OK) return 193;
        \\    if (sa_json_free(json_root) != SA_STD_ERR_INVALID_HANDLE) return 194;
        \\    if (sa_json_parse((const uint8_t *)"{", 1) != 0) return 195;
        \\    json_root = sa_json_parse(json_doc, sizeof(json_doc) - 1);
        \\    json_child = 42;
        \\    if (sa_json_object_get(json_root, (const uint8_t *)"missing", 7, &json_child) != SA_STD_ERR_NOT_FOUND || json_child != 0) return 196;
        \\    json_child = 42;
        \\    if (sa_json_array_get(json_root, 0, &json_child) != SA_STD_ERR_INVALID_ARGUMENT || json_child != 0) return 197;
        \\    json_i64 = 42;
        \\    if (sa_json_object_get_i64(json_root, (const uint8_t *)"name", 4, &json_i64) != SA_STD_ERR_INVALID_ARGUMENT || json_i64 != 0) return 198;
        \\    json_ptr = (const uint8_t *)1;
        \\    json_len = 42;
        \\    if (sa_json_object_get_string(json_root, (const uint8_t *)"missing", 7, &json_ptr, &json_len) != SA_STD_ERR_NOT_FOUND || json_ptr != 0 || json_len != 0) return 199;
        \\    if (sa_json_free(json_root) != SA_STD_OK) return 200;
        \\    json_root = sa_json_parse(json_doc, sizeof(json_doc) - 1);
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 1, 0, 0, 0, &json_writer) != SA_STD_OK) return 201;
        \\    if (sa_json_writer_begin_object(json_writer) != SA_STD_OK) return 202;
        \\    if (sa_json_writer_field_string(json_writer, (const uint8_t *)"name", 4, (const uint8_t *)"win", 3) != SA_STD_OK) return 203;
        \\    if (sa_json_writer_field_bool(json_writer, (const uint8_t *)"ok", 2, 1) != SA_STD_OK) return 204;
        \\    if (sa_json_writer_field_i64(json_writer, (const uint8_t *)"count", 5, 9) != SA_STD_OK) return 205;
        \\    if (sa_json_writer_field_f64(json_writer, (const uint8_t *)"ratio", 5, 2.5) != SA_STD_OK) return 206;
        \\    if (sa_json_writer_field_null(json_writer, (const uint8_t *)"none", 4) != SA_STD_OK) return 207;
        \\    if (sa_json_object_get(json_root, (const uint8_t *)"items", 5, &json_child) != SA_STD_OK) return 208;
        \\    if (sa_json_writer_field_node(json_writer, (const uint8_t *)"items", 5, json_child) != SA_STD_OK) return 209;
        \\    if (sa_json_writer_object_field(json_writer, (const uint8_t *)"extra", 5) != SA_STD_OK) return 210;
        \\    if (sa_json_writer_begin_array(json_writer) != SA_STD_OK) return 211;
        \\    if (sa_json_writer_write_i64(json_writer, 3) != SA_STD_OK || sa_json_writer_write_string(json_writer, (const uint8_t *)"x", 1) != SA_STD_OK) return 212;
        \\    if (sa_json_writer_write_bool(json_writer, 0) != SA_STD_OK || sa_json_writer_write_null(json_writer) != SA_STD_OK) return 213;
        \\    if (sa_json_writer_end_array(json_writer) != SA_STD_OK || sa_json_writer_end_object(json_writer) != SA_STD_OK) return 214;
        \\    if (sa_json_writer_finish(json_writer, &json_buffer) != SA_STD_OK || json_buffer == 0) return 215;
        \\    json_ptr = sa_json_buffer_data(json_buffer);
        \\    json_len = sa_json_buffer_len(json_buffer);
        \\    json_written_root = sa_json_parse(json_ptr, json_len);
        \\    if (json_written_root == 0 || sa_json_object_get_i64(json_written_root, (const uint8_t *)"count", 5, &json_i64) != SA_STD_OK || json_i64 != 9) return 216;
        \\    if (sa_json_object_get_string(json_written_root, (const uint8_t *)"name", 4, &json_ptr, &json_len) != SA_STD_OK || json_len != 3 || memcmp(json_ptr, "win", 3) != 0) return 217;
        \\    if (sa_json_object_get(json_written_root, (const uint8_t *)"extra", 5, &json_item) != SA_STD_OK || sa_json_value_count(json_item, &len) != SA_STD_OK || len != 4) return 218;
        \\    if (sa_json_free(json_item) != SA_STD_OK || sa_json_free(json_written_root) != SA_STD_OK || sa_json_free(json_child) != SA_STD_OK || sa_json_free(json_root) != SA_STD_OK) return 219;
        \\    if (sa_json_buffer_free(json_buffer) != SA_STD_OK || sa_json_writer_free(json_writer) != SA_STD_OK) return 220;
        \\    if (sa_json_writer_free(json_writer) != SA_STD_ERR_INVALID_HANDLE) return 221;
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 0, 0, 0, 0, &json_writer) != SA_STD_OK) return 222;
        \\    if (sa_json_writer_begin_object(json_writer) != SA_STD_OK) return 223;
        \\    json_buffer = 42;
        \\    if (sa_json_writer_finish(json_writer, &json_buffer) != SA_STD_ERR_INVALID_ARGUMENT || json_buffer != 0) return 224;
        \\    if (sa_json_writer_end_object(json_writer) != SA_STD_OK || sa_json_writer_finish(json_writer, &json_buffer) != SA_STD_OK) return 225;
        \\    if (sa_json_writer_finish(json_writer, &json_item) != SA_STD_ERR_INVALID_HANDLE || json_item != 0) return 226;
        \\    if (sa_json_buffer_free(json_buffer) != SA_STD_OK || sa_json_writer_free(json_writer) != SA_STD_OK) return 227;
        \\    if (sa_json_scanner_new(&json_scanner) != SA_STD_OK || json_scanner == 0) return 228;
        \\    if (sa_json_scanner_feed(json_scanner, json_chunk1, sizeof(json_chunk1) - 1) != SA_STD_OK) return 229;
        \\    if (sa_json_scanner_feed(json_scanner, json_chunk2, sizeof(json_chunk2) - 1) != SA_STD_ERR_INVALID_ARGUMENT) return 230;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_OBJECT_BEGIN) return 231;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_STRING || json_token.text_len != 4 || memcmp(json_token.text_ptr, "name", 4) != 0) return 232;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_PARTIAL_STRING || json_token.text_len != 1 || memcmp(json_token.text_ptr, "s", 1) != 0) return 233;
        \\    if (sa_json_scanner_feed(json_scanner, json_chunk2, sizeof(json_chunk2) - 1) != SA_STD_OK) return 234;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_STRING || json_token.text_len != 2 || memcmp(json_token.text_ptr, "ci", 2) != 0) return 235;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_STRING || json_token.text_len != 5 || memcmp(json_token.text_ptr, "count", 5) != 0) return 236;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_ERR_TRUNCATED || json_token.kind != SA_JSON_TOKEN_INVALID) return 237;
        \\    if (sa_json_scanner_feed(json_scanner, json_chunk3, sizeof(json_chunk3) - 1) != SA_STD_OK) return 238;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_NUMBER || json_token.text_len != 1 || memcmp(json_token.text_ptr, "7", 1) != 0) return 239;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_OBJECT_END) return 240;
        \\    if (sa_json_scanner_end_input(json_scanner) != SA_STD_OK) return 241;
        \\    if (sa_json_scanner_next(json_scanner, &json_token) != SA_STD_OK || json_token.kind != SA_JSON_TOKEN_END_OF_DOCUMENT) return 242;
        \\    if (sa_json_scanner_free(json_scanner) != SA_STD_OK || sa_json_scanner_free(json_scanner) != SA_STD_ERR_INVALID_HANDLE) return 243;
        \\    json_stream = sa_json_stream_new((const uint8_t *)"[\"x\",2]", 7);
        \\    if (json_stream == 0 || sa_json_stream_next(json_stream) != SA_JSON_TOKEN_ARRAY_BEGIN) return 244;
        \\    if (sa_json_stream_next(json_stream) != SA_JSON_TOKEN_STRING) return 245;
        \\    json_ptr = sa_json_stream_get_slice_ptr(json_stream);
        \\    json_len = sa_json_stream_get_slice_len(json_stream);
        \\    if (json_ptr == 0 || json_len != 1 || json_ptr[0] != 'x') return 246;
        \\    if (sa_json_stream_next(json_stream) != SA_JSON_TOKEN_NUMBER) return 247;
        \\    json_ptr = sa_json_stream_get_slice_ptr(json_stream);
        \\    if (json_ptr == 0 || sa_json_stream_get_slice_len(json_stream) != 1 || json_ptr[0] != '2') return 248;
        \\    if (sa_json_stream_next(json_stream) != SA_JSON_TOKEN_ARRAY_END || sa_json_stream_next(json_stream) != SA_JSON_TOKEN_END_OF_DOCUMENT) return 249;
        \\    if (sa_json_stream_free(json_stream) != SA_STD_OK || sa_json_stream_next(json_stream) != SA_JSON_TOKEN_INVALID) return 250;
        \\    if (sa_std_fs_open_write(handle_io_path, sizeof(handle_io_path) - 1, 1, &file_handle) != SA_STD_OK || file_handle == 0) return 251;
        \\    if (sa_std_write(file_handle, handle_payload, 2, &io_count) != SA_STD_OK || io_count != 2) return 252;
        \\    if (sa_io_write_all(file_handle, handle_payload + 2, 4) != SA_STD_OK || sa_io_flush(file_handle) != SA_STD_OK) return 253;
        \\    if (sa_std_fs_file_write_all_at(file_handle, (const uint8_t *)"XY", 2, 2) != SA_STD_OK) return 254;
        \\    if (sa_std_fs_file_seek(file_handle, 0, 0, &io_pos) != SA_STD_OK || io_pos != 0) return 255;
        \\    if (sa_io_read_exact(file_handle, io_data, 6) != SA_STD_OK || memcmp(io_data, "abXYef", 6) != 0) return 256;
        \\    if (sa_fs_file_sync(file_handle) != SA_STD_OK || sa_io_close(file_handle) != SA_STD_OK) return 257;
        \\    if (sa_io_close(file_handle) != SA_STD_ERR_INVALID_HANDLE) return 258;
        \\    file_handle = 99;
        \\    if (sa_std_fs_open_read(handle_io_path, sizeof(handle_io_path) - 1, &file_handle) != SA_STD_OK || file_handle == 0) return 259;
        \\    memset(io_data, 0, sizeof(io_data));
        \\    if (sa_std_fs_file_read_at(file_handle, io_data, 2, 2, &io_count) != SA_STD_OK || io_count != 2 || memcmp(io_data, "XY", 2) != 0) return 260;
        \\    if (sa_std_fs_file_read_exact_at(file_handle, io_data, 7, 0) != SA_STD_ERR_TRUNCATED) return 261;
        \\    if (sa_io_close(file_handle) != SA_STD_OK) return 262;
        \\    file_handle = 99;
        \\    if (sa_std_fs_open_write(handle_io_path, sizeof(handle_io_path) - 1, 0, &file_handle) != SA_STD_OK || file_handle == 0) return 263;
        \\    if (sa_fs_file_truncate(file_handle, 3) != SA_STD_OK || sa_fs_file_sync_data(file_handle) != SA_STD_OK) return 264;
        \\    if (sa_io_close(file_handle) != SA_STD_OK || sa_std_fs_len(handle_io_path, sizeof(handle_io_path) - 1, &len) != SA_STD_OK || len != 3) return 265;
        \\    io_count = 99;
        \\    if (sa_std_read(0x710000000000ffffULL, io_data, sizeof(io_data), &io_count) != SA_STD_ERR_INVALID_HANDLE || io_count != 0) return 266;
        \\    io_count = 99;
        \\    if (sa_std_write(0x710000000000ffffULL, handle_payload, sizeof(handle_payload) - 1, &io_count) != SA_STD_ERR_INVALID_HANDLE || io_count != 0) return 267;
        \\    file_handle = 99;
        \\    if (sa_std_fs_open_read(0, 1, &file_handle) != SA_STD_ERR_INVALID_ARGUMENT || file_handle != 0) return 268;
        \\    if (sa_std_fs_remove(handle_io_path, sizeof(handle_io_path) - 1) != SA_STD_OK) return 269;
        \\    if (sa_fs_write_file(path, sizeof(path) - 1, payload, sizeof(payload) - 1) != SA_STD_OK) return 151;
        \\    metadata_result = sa_fs_metadata(path, sizeof(path) - 1);
        \\    if (metadata_result.status != SA_STD_OK || metadata_result.value == 0) return 152;
        \\    if (sa_fs_metadata_is_file(metadata_result.value) != 1 || sa_fs_metadata_is_directory(metadata_result.value) != 0 || sa_fs_metadata_is_symlink(metadata_result.value) != 0) return 153;
        \\    if (sa_fs_metadata_len(metadata_result.value) != sizeof(payload) - 1 || sa_fs_metadata_st_size(metadata_result.value) != sizeof(payload) - 1) return 154;
        \\    if (sa_fs_metadata_mode(metadata_result.value) != 0 || sa_fs_metadata_uid(metadata_result.value) != 0 || sa_fs_metadata_gid(metadata_result.value) != 0) return 155;
        \\    if (sa_fs_metadata_modified_ms(metadata_result.value) <= 0 || sa_fs_metadata_accessed_ms(metadata_result.value) <= 0 || sa_fs_metadata_st_mtime(metadata_result.value) <= 0) return 156;
        \\    metadata_free_result = sa_fs_metadata_free(metadata_result.value);
        \\    if (metadata_free_result.status != SA_STD_OK || metadata_free_result.value != 0) return 157;
        \\    metadata_free_result = sa_fs_metadata_free(metadata_result.value);
        \\    if (metadata_free_result.status != SA_STD_ERR_INVALID_HANDLE) return 158;
        \\    if (sa_fs_make_dir(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 159;
        \\    metadata_result = sa_fs_metadata(root_dir, sizeof(root_dir) - 1);
        \\    if (metadata_result.status != SA_STD_OK || metadata_result.value == 0) return 160;
        \\    if (sa_fs_metadata_is_directory(metadata_result.value) != 1) return 166;
        \\    if (sa_std_fs_metadata_free(metadata_result.value) != SA_STD_OK) return 167;
        \\    if (sa_fs_remove_dir(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 161;
        \\    metadata_json_result = sa_fs_metadata_json(path, sizeof(path) - 1);
        \\    if (metadata_json_result.status != SA_STD_OK || !expect_buffer(metadata_json_result.value, "\"isFile\":true")) return 162;
        \\    metadata_result = sa_fs_metadata((const uint8_t *)"missing-metadata", 16);
        \\    if (metadata_result.status != SA_STD_ERR_NOT_FOUND || metadata_result.value != 0) return 163;
        \\    handle = 99;
        \\    if (sa_std_fs_metadata((const uint8_t *)"missing-metadata", 16, &handle) != SA_STD_ERR_NOT_FOUND || handle != 0) return 164;
        \\    if (sa_std_fs_remove(path, sizeof(path) - 1) != SA_STD_OK) return 165;
        \\    if (sa_fs_make_dir(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 168;
        \\    if (sa_fs_write_file(leaf_dir, sizeof(leaf_dir) - 1, payload, sizeof(payload) - 1) != SA_STD_OK) return 169;
        \\    dir_result = sa_fs_read_dir_json(root_dir, sizeof(root_dir) - 1, 1);
        \\    if (dir_result.status != SA_STD_OK || !expect_buffer(dir_result.value, "\"entries\":[")) return 170;
        \\    dir_result = sa_fs_read_dir_json(root_dir, sizeof(root_dir) - 1, 0);
        \\    if (dir_result.status != SA_STD_OK || !expect_buffer(dir_result.value, "\"entries\":[]")) return 171;
        \\    dir_result = sa_fs_read_dir_entries(root_dir, sizeof(root_dir) - 1, 4);
        \\    if (dir_result.status != SA_STD_OK || dir_result.value == 0 || sa_fs_dir_entries_len(dir_result.value) != 1) return 181;
        \\    if (sa_std_fs_dir_entries_get(dir_result.value, 0, &dir_entry) != SA_STD_OK || dir_entry == 0) return 182;
        \\    if (sa_fs_dir_entry_kind(dir_entry) != 1 || sa_fs_dir_entry_ino(dir_entry) != 0) return 183;
        \\    if (sa_fs_dir_entries_free(dir_result.value) != SA_STD_OK) return 184;
        \\    dir_name = sa_fs_dir_entry_name_ptr(dir_entry);
        \\    if (dir_name == 0 || sa_fs_dir_entry_name_len(dir_entry) != 4 || memcmp(dir_name, "leaf", 4) != 0) return 185;
        \\    if (sa_fs_dir_entry_file_name_ptr(dir_entry) != dir_name || sa_fs_dir_entry_file_name_len(dir_entry) != 4) return 186;
        \\    if (sa_fs_dir_entry_free(dir_entry) != SA_STD_OK || sa_fs_dir_entry_free(dir_entry) != SA_STD_ERR_INVALID_HANDLE) return 187;
        \\    dir_result = sa_fs_read_dir_entries(root_dir, sizeof(root_dir) - 1, 4);
        \\    dir_entry = 99;
        \\    if (sa_std_fs_dir_entries_get(dir_result.value, 1, &dir_entry) != SA_STD_ERR_INVALID_ARGUMENT || dir_entry != 0) return 188;
        \\    if (sa_fs_dir_entries_free(dir_result.value) != SA_STD_OK || sa_fs_dir_entries_free(dir_result.value) != SA_STD_ERR_INVALID_HANDLE) return 189;
        \\    dir_result = sa_fs_read_dir_entries((const uint8_t *)"missing-dir", 11, 4);
        \\    if (dir_result.status != SA_STD_ERR_NOT_FOUND || dir_result.value != 0) return 190;
        \\    if (sa_fs_remove_file(leaf_dir, sizeof(leaf_dir) - 1) != SA_STD_OK || sa_fs_remove_dir(root_dir, sizeof(root_dir) - 1) != SA_STD_OK) return 191;
        \\    if (sa_fs_write_file(path, sizeof(path) - 1, payload, sizeof(payload) - 1) != SA_STD_OK) return 192;
        \\    if (sa_fs_hard_link(path, sizeof(path) - 1, hard_link_path, sizeof(hard_link_path) - 1) != SA_STD_OK) return 193;
        \\    if (sa_std_fs_len(hard_link_path, sizeof(hard_link_path) - 1, &len) != SA_STD_OK || len != sizeof(payload) - 1) return 194;
        \\    if (sa_fs_set_times_ms(path, sizeof(path) - 1, 1700000000000LL, 1700000001000LL) != SA_STD_OK) return 195;
        \\    metadata_result = sa_fs_metadata(path, sizeof(path) - 1);
        \\    if (metadata_result.status != SA_STD_OK || sa_fs_metadata_modified_ms(metadata_result.value) != 1700000001000LL || sa_std_fs_metadata_free(metadata_result.value) != SA_STD_OK) return 196;
        \\    handle = 99;
        \\    if (sa_std_fs_open_options(path, sizeof(path) - 1, 1, 0, 0, &handle) != SA_STD_ERR_UNSUPPORTED || handle != 0) return 197;
        \\    handle = 99;
        \\    if (sa_std_fs_file_from_raw_fd(1, &handle) != SA_STD_ERR_UNSUPPORTED || handle != 0) return 198;
        \\    if (sa_fs_make_dir_mode(root_dir, sizeof(root_dir) - 1, 0755) != SA_STD_ERR_UNSUPPORTED) return 199;
        \\    if (sa_fs_create_dir_mode(root_dir, sizeof(root_dir) - 1, 0755) != SA_STD_ERR_UNSUPPORTED) return 200;
        \\    if (sa_fs_set_permissions(path, sizeof(path) - 1, 0644) != SA_STD_ERR_UNSUPPORTED) return 201;
        \\    if (sa_fs_chown(path, sizeof(path) - 1, 1, 1, 1, 1) != SA_STD_ERR_UNSUPPORTED || sa_fs_lchown(path, sizeof(path) - 1, 1, 1, 1, 1) != SA_STD_ERR_UNSUPPORTED) return 202;
        \\    if (sa_fs_fchown(0, 1, 1, 1, 1) != SA_STD_ERR_UNSUPPORTED || sa_fs_chroot(root_dir, sizeof(root_dir) - 1) != SA_STD_ERR_UNSUPPORTED || sa_fs_mkfifo(path, sizeof(path) - 1, 0600) != SA_STD_ERR_UNSUPPORTED) return 203;
        \\    if (sa_std_fs_remove(hard_link_path, sizeof(hard_link_path) - 1) != SA_STD_OK || sa_std_fs_remove(path, sizeof(path) - 1) != SA_STD_OK) return 204;
        \\    return 0;
        \\}
    ;
    try writeSource(tmp.dir, "sa_std_windows_smoke.c", c_source);
    try writeSource(tmp.dir, "process_fixture.cmd", "@echo process-out\r\n@echo process-err>&2\r\n@exit /b 7\r\n");
    try writeSource(tmp.dir, "wait_fixture.cmd", "@ping -n 6 127.0.0.1 >nul\r\n@exit /b 0\r\n");
    try tmp.dir.makeDir("process_cwd");
    try writeSource(tmp.dir, "process_cwd/cwd_fixture.cmd", "@echo cwd-ok\r\n@exit /b 0\r\n");

    const exe_name = "sa_std_windows_smoke.exe";
    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "sa_std_windows_smoke.c",
        build_options.sa_std_archive_path,
        "-lc",
        "-lws2_32",
        "-liphlpapi",
        "-o",
        exe_name,
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{exe_name});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std windows ok\n", run_result.stdout);
}

