const std = @import("std");
const sio = @import("sio");
const copyRuntimeArchiveToCwd = @import("helpers.zig").copyRuntimeArchiveToCwd;
const expectSuccess = @import("helpers.zig").expectSuccess;
const icu_demo_link_args = @import("helpers.zig").icu_demo_link_args;
const runCommand = @import("helpers.zig").runCommand;
const writeSource = @import("helpers.zig").writeSource;

test "sa_std regex compile match and group access are usable from C" {
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
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t pattern[] = "h([a-z]+)o ([a-z]+)";
        \\    const uint8_t text[] = "hello world";
        \\    uint64_t regex = 0;
        \\    uint64_t match = 0;
        \\    const uint8_t *group0 = NULL;
        \\    const uint8_t *group1 = NULL;
        \\    const uint8_t *group2 = NULL;
        \\    uint64_t group0_len = 0;
        \\    uint64_t group1_len = 0;
        \\    uint64_t group2_len = 0;
        \\    uint64_t group_count = 0;
        \\
        \\    regex = sa_regex_compile(pattern, sizeof(pattern) - 1, SA_REGEX_EXTENDED);
        \\    if (regex == 0) return 2;
        \\    group_count = sa_regex_group_count(regex);
        \\    if (group_count != 3) return 3;
        \\    match = sa_regex_match(regex, text, sizeof(text) - 1);
        \\    if (match == 0) return 4;
        \\    group0 = sa_regex_group_ptr(match, 0);
        \\    group1 = sa_regex_group_ptr(match, 1);
        \\    group2 = sa_regex_group_ptr(match, 2);
        \\    group0_len = sa_regex_group_len(match, 0);
        \\    group1_len = sa_regex_group_len(match, 1);
        \\    group2_len = sa_regex_group_len(match, 2);
        \\    if (group0 == NULL || group1 == NULL || group2 == NULL) return 5;
        \\    if (group0_len != 11 || memcmp(group0, "hello world", 11) != 0) return 6;
        \\    if (group1_len != 3 || memcmp(group1, "ell", 3) != 0) return 7;
        \\    if (group2_len != 5 || memcmp(group2, "world", 5) != 0) return 8;
        \\    if (sa_regex_match_free(match) != SA_STD_OK) return 9;
        \\    if (sa_regex_free(regex) != SA_STD_OK) return 10;
        \\    puts("sa_std regex ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "regex.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "regex.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_regex_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_regex_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std regex ok"));
}

test "sa_std time exports are usable from C" {
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
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <time.h>
        \\
        \\static int check_utc(const SaTimeDate *dt, int64_t unix_s) {
        \\    struct tm tm_utc;
        \\    time_t secs = (time_t)unix_s;
        \\
        \\    memset(&tm_utc, 0, sizeof(tm_utc));
        \\    if (gmtime_r(&secs, &tm_utc) == NULL) return 0;
        \\    if (dt->year != (uint16_t)(tm_utc.tm_year + 1900)) return 0;
        \\    if (dt->month != (uint8_t)(tm_utc.tm_mon + 1)) return 0;
        \\    if (dt->day != (uint8_t)tm_utc.tm_mday) return 0;
        \\    if (dt->hour != (uint8_t)tm_utc.tm_hour) return 0;
        \\    if (dt->minute != (uint8_t)tm_utc.tm_min) return 0;
        \\    if (dt->second != (uint8_t)tm_utc.tm_sec) return 0;
        \\    return 1;
        \\}
        \\
        \\int main(void) {
        \\    uint64_t mono_ns_0 = 0;
        \\    uint64_t mono_ns_1 = 0;
        \\    int64_t unix_s = 0;
        \\    int64_t unix_ms = 0;
        \\    int64_t unix_ns = 0;
        \\    SaTimeDate dt = {0};
        \\
        \\    mono_ns_0 = sa_time_instant_ns();
        \\    if (sa_time_sleep_ms(1) != SA_STD_OK) return 3;
        \\    mono_ns_1 = sa_time_instant_ns();
        \\    if (mono_ns_1 <= mono_ns_0) return 5;
        \\    unix_s = sa_time_unix_s();
        \\    unix_ms = sa_time_unix_ms();
        \\    unix_ns = sa_time_unix_ns();
        \\    if (unix_s == 0 && unix_ms == 0 && unix_ns == 0) return 6;
        \\    if (sa_time_utc_now(&dt) != SA_STD_OK) return 9;
        \\    if (sa_time_sleep_ns(0) != SA_STD_OK) return 10;
        \\    if (unix_s < 0 || unix_ms < 0 || unix_ns < 0) return 11;
        \\    if (unix_ms / 1000 != unix_s) return 12;
        \\    if (unix_ns / 1000000 != unix_ms) return 13;
        \\    if (dt.unix_ms != unix_ms) return 14;
        \\    if (dt.unix_ns / 1000000 != unix_ms) return 15;
        \\    if (dt.millisecond != (uint16_t)(unix_ms % 1000)) return 16;
        \\    if (!check_utc(&dt, unix_s)) return 17;
        \\    puts("sa_std time ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "time.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "time.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_time_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_time_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std time ok\n", run_result.stdout);
}

test "sa_std Deno facade runtime helpers are usable from C" {
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
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\static int valid_uuid(const uint8_t *s, uint64_t n) {
        \\    if (n != 36) return 0;
        \\    if (s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-') return 0;
        \\    if (s[14] != '4') return 0;
        \\    if (!(s[19] == '8' || s[19] == '9' || s[19] == 'a' || s[19] == 'b')) return 0;
        \\    return 1;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t key[] = "SA_DENO_FACADE_TEST";
        \\    const uint8_t value[] = "ok-value";
        \\    uint64_t cwd = 0;
        \\    uint64_t got = 0;
        \\    uint64_t uuid = 0;
        \\    uint64_t now_iso = 0;
        \\    uint64_t args = 0;
        \\    uint8_t *ptr = 0;
        \\    uint64_t len = 0;
        \\
        \\    cwd = sa_deno_cwd();
        \\    if (cwd == 0) return 2;
        \\    ptr = sa_fs_read_buffer_data(cwd);
        \\    len = sa_fs_read_buffer_len(cwd);
        \\    if (ptr == 0 || len == 0) return 3;
        \\    if (sa_fs_read_buffer_free(cwd) != SA_STD_OK) return 4;
        \\
        \\    if (sa_deno_env_set(key, sizeof(key) - 1, value, sizeof(value) - 1) != SA_STD_OK) return 5;
        \\    got = sa_env_get(key, sizeof(key) - 1);
        \\    if (got == 0) return 6;
        \\    ptr = sa_env_buffer_data(got);
        \\    len = sa_env_buffer_len(got);
        \\    if (ptr == 0 || len != sizeof(value) - 1 || memcmp(ptr, value, sizeof(value) - 1) != 0) return 7;
        \\    if (sa_env_buffer_free(got) != SA_STD_OK) return 8;
        \\    if (sa_deno_env_delete(key, sizeof(key) - 1) != SA_STD_OK) return 9;
        \\    if (sa_env_get(key, sizeof(key) - 1) != 0) return 10;
        \\
        \\    uuid = sa_deno_random_uuid();
        \\    if (uuid == 0) return 11;
        \\    ptr = sa_fmt_buffer_data(uuid);
        \\    len = sa_fmt_buffer_len(uuid);
        \\    if (!valid_uuid(ptr, len)) return 12;
        \\    if (sa_fmt_buffer_free(uuid) != SA_STD_OK) return 13;
        \\
        \\    now_iso = sa_deno_date_now_iso();
        \\    if (now_iso == 0) return 14;
        \\    ptr = sa_fs_read_buffer_data(now_iso);
        \\    len = sa_fs_read_buffer_len(now_iso);
        \\    if (ptr == 0 || len != 24) return 15;
        \\    if (ptr[4] != '-' || ptr[7] != '-' || ptr[10] != 'T' || ptr[13] != ':' || ptr[16] != ':' || ptr[19] != '.' || ptr[23] != 'Z') return 16;
        \\    if (sa_fs_read_buffer_free(now_iso) != SA_STD_OK) return 17;
        \\
        \\    args = sa_deno_args_json();
        \\    if (args == 0) return 18;
        \\    ptr = sa_fs_read_buffer_data(args);
        \\    len = sa_fs_read_buffer_len(args);
        \\    if (ptr == 0 || len != 2 || memcmp(ptr, "[]", 2) != 0) return 19;
        \\    if (sa_fs_read_buffer_free(args) != SA_STD_OK) return 20;
        \\
        \\    puts("sa_std deno facade ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "deno_facade.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "deno_facade.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_facade_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_deno_facade_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std deno facade ok\n", run_result.stdout);
}
