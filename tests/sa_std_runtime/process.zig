const std = @import("std");
const sio = @import("sio");
const copyRuntimeArchiveToCwd = @import("helpers.zig").copyRuntimeArchiveToCwd;
const expectSuccess = @import("helpers.zig").expectSuccess;
const icu_demo_link_args = @import("helpers.zig").icu_demo_link_args;
const runCommand = @import("helpers.zig").runCommand;
const writeSource = @import("helpers.zig").writeSource;

test "sa_std fmt and process exports are usable from C" {
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
        \\#include <signal.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <sys/wait.h>
        \\#include <unistd.h>
        \\
        \\int main(void) {
        \\    uint64_t fmt_handle = sa_fmt_i64(42, 10);
        \\    uint64_t out_len = 0;
        \\    char buffer[16] = {0};
        \\    if (fmt_handle == 0) return 2;
        \\    if (sa_fmt_buffer_len(fmt_handle) != 2) return 3;
        \\    if (sa_fmt_buffer_write_to(fmt_handle, SA_STD_STDOUT) != SA_STD_OK) return 4;
        \\    if (sa_fmt_buffer_free(fmt_handle) != SA_STD_OK) return 5;
        \\    if (sa_fmt_i64(-7, 10) == 0) return 6;
        \\    if (sa_fmt_i64_into(-42, 10, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 12;
        \\    if (out_len != 3 || memcmp(buffer, "-42", 3) != 0) return 13;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_fmt_u64_into(255, 16, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 14;
        \\    if (out_len != 2 || memcmp(buffer, "ff", 2) != 0) return 15;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_fmt_bool_into(1, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 16;
        \\    if (out_len != 4 || memcmp(buffer, "true", 4) != 0) return 17;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_fmt_bytes_into((const uint8_t *)"abc", 3, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 18;
        \\    if (out_len != 3 || memcmp(buffer, "abc", 3) != 0) return 19;
        \\    if (sa_fmt_i64_into(12345, 10, (uint8_t *)buffer, 2, &out_len) != SA_STD_ERR_TRUNCATED) return 20;
        \\    if (out_len != 5) return 21;
        \\
        \\    SaProcessArgv argv[3];
        \\    argv[0].data = (const uint8_t *)"/bin/sh";
        \\    argv[0].len = 7;
        \\    argv[1].data = (const uint8_t *)"-c";
        \\    argv[1].len = 2;
        \\    argv[2].data = (const uint8_t *)"printf sa_std_runtime; printf sa_std_error >&2";
        \\    argv[2].len = 46;
        \\    uint64_t process = 0;
        \\    uint32_t code = 0;
        \\    if (sa_std_process_id() == 0) return 28;
        \\    if (sa_std_process_run(argv, 3, &process) != SA_STD_OK) return 7;
        \\    if (process == 0) return 8;
        \\    if (sa_std_process_wait(process, &code) != SA_STD_OK) return 9;
        \\    if (code != 0) return 10;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_std_process_read_stdout(process, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 22;
        \\    if (out_len != 14 || memcmp(buffer, "sa_std_runtime", 14) != 0) return 23;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_std_process_read_stderr(process, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 26;
        \\    if (out_len != 12 || memcmp(buffer, "sa_std_error", 12) != 0) return 27;
        \\    memset(buffer, 0, sizeof(buffer));
        \\    if (sa_io_read(process, (uint8_t *)buffer, sizeof(buffer), &out_len) != SA_STD_OK) return 24;
        \\    if (out_len != 0) return 25;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 11;
        \\
        \\    argv[0].data = (const uint8_t *)"/bin/sh";
        \\    argv[0].len = 7;
        \\    argv[1].data = (const uint8_t *)"-c";
        \\    argv[1].len = 2;
        \\    argv[2].data = (const uint8_t *)"sleep 5";
        \\    argv[2].len = 7;
        \\    process = 0;
        \\    code = 0;
        \\    int32_t ready = -1;
        \\    uint32_t child_pid = 0;
        \\    if (sa_std_process_spawn(argv, 3, &process) != SA_STD_OK) return 29;
        \\    if (process == 0) return 30;
        \\    if (sa_std_process_child_id(process, &child_pid) != SA_STD_OK) return 37;
        \\    if (child_pid == 0) return 38;
        \\    if (sa_std_process_try_wait(process, &ready, &code) != SA_STD_OK) return 31;
        \\    if (ready != 0 || code != 0) return 32;
        \\    if (sa_std_process_kill(process) != SA_STD_OK) return 33;
        \\    ready = 0;
        \\    code = 0;
        \\    if (sa_std_process_try_wait(process, &ready, &code) != SA_STD_OK) return 34;
        \\    if (ready != 1 || code == 0) return 35;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 36;
        \\    pid_t abort_pid = fork();
        \\    if (abort_pid < 0) return 39;
        \\    if (abort_pid == 0) {
        \\        sa_std_process_abort();
        \\        _exit(40);
        \\    }
        \\    int abort_status = 0;
        \\    if (waitpid(abort_pid, &abort_status, 0) != abort_pid) return 41;
        \\    if (!WIFSIGNALED(abort_status) || WTERMSIG(abort_status) != SIGABRT) return 42;
        \\    puts("sa_std fmt/process ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_fmtdemo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_fmtdemo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std fmt/process ok"));
}

test "sa_std process bidi spawn round-trips stdin to stdout from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

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
\\    SaProcessArgv argv[1];
\\    argv[0].data = (const uint8_t *)"/bin/cat";
\\    argv[0].len = 8;
\\    uint64_t process = 0;
\\    uint64_t stdin_h = 0;
\\    uint64_t stdout_h = 0;
\\    uint64_t stderr_h = 0;
\\    if (sa_std_process_spawn_bidi(argv, 1, &process, &stdin_h, &stdout_h, &stderr_h) != SA_STD_OK) return 2;
\\    if (process == 0 || stdin_h == 0 || stdout_h == 0 || stderr_h == 0) return 3;
\\    const char *msg = "bidi-roundtrip\n";
\\    uint64_t written = 0;
\\    if (sa_io_write(stdin_h, (const uint8_t *)msg, 15, &written) != SA_STD_OK) return 4;
\\    if (written != 15) return 5;
\\    if (sa_std_close(stdin_h) != SA_STD_OK) return 6;
\\    char buf[64];
\\    uint64_t total = 0;
\\    uint64_t n = 0;
\\    for (;;) {
\\        if (sa_io_read(stdout_h, (uint8_t *)buf + total, sizeof(buf) - total, &n) != SA_STD_OK) return 7;
\\        if (n == 0) break;
\\        total += n;
\\        if (total >= sizeof(buf)) return 8;
\\    }
\\    if (total != 15 || memcmp(buf, msg, 15) != 0) return 9;
\\    uint64_t en = 1;
\\    if (sa_io_read(stderr_h, (uint8_t *)buf, sizeof(buf), &en) != SA_STD_OK) return 10;
\\    if (en != 0) return 11;
\\    uint32_t code = 99;
\\    if (sa_std_process_wait(process, &code) != SA_STD_OK) return 12;
\\    if (code != 0) return 13;
\\    if (sa_std_close(stdout_h) != SA_STD_OK) return 14;
\\    if (sa_std_close(stderr_h) != SA_STD_OK) return 15;
\\    if (sa_std_process_close(process) != SA_STD_OK) return 16;
\\    if (sa_std_process_spawn_bidi(argv, 1, &process, 0, &stdout_h, &stderr_h) != SA_STD_ERR_INVALID_ARGUMENT) return 17;
\\    process = 0;
\\    stdin_h = 0;
\\    stdout_h = 0;
\\    stderr_h = 0;
\\    if (sa_std_process_spawn_bidi_cwd(argv, 1, (const uint8_t *)"/tmp", 4, &process, &stdin_h, &stdout_h, &stderr_h) != SA_STD_OK) return 18;
\\    if (sa_std_close(stdin_h) != SA_STD_OK) return 19;
\\    code = 99;
\\    if (sa_std_process_wait(process, &code) != SA_STD_OK) return 20;
\\    if (code != 0) return 21;
\\    if (sa_std_close(stdout_h) != SA_STD_OK) return 22;
\\    if (sa_std_close(stderr_h) != SA_STD_OK) return 23;
\\    if (sa_std_process_close(process) != SA_STD_OK) return 24;
\\    puts("sa_std process bidi ok");
\\    return 0;
\\}
\\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_bididemo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_bididemo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std process bidi ok"));
}

test "sa_std detached pthread export runs without join" {
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
        \\#include <time.h>
        \\
        \\static volatile int32_t shared_value = 0;
        \\
        \\static int32_t worker(uint8_t *arg) {
        \\    volatile int32_t *slot = (volatile int32_t *)arg;
        \\    *slot = 42;
        \\    return 0;
        \\}
        \\
        \\int main(void) {
        \\    struct timespec delay = {0, 1000000};
        \\    if (pthread_spawn_detached((const uint8_t *)(uintptr_t)&worker, (const uint8_t *)&shared_value) != SA_STD_OK) return 2;
        \\    for (int i = 0; i < 1000 && shared_value != 42; i += 1) {
        \\        nanosleep(&delay, 0);
        \\    }
        \\    if (shared_value != 42) return 3;
        \\    puts("sa_std pthread detached ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "pthread_detached.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "pthread_detached.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_pthread_detached_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_pthread_detached_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std pthread detached ok"));
}
