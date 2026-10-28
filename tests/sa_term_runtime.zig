const std = @import("std");
const sio = @import("sio");
const builtin = @import("builtin");

// Static demos link libsa_std.a, which carries no link dependencies, so
// demos add the ICU libraries the Unicode runtime (sa_unicode_normalize)
// needs on Linux themselves. Empty elsewhere; other platforms arrange ICU
// differently and must not gain a bogus -licuuc flag.
const icu_demo_link_args: [if (builtin.os.tag == .linux) 2 else 0][]const u8 = if (builtin.os.tag == .linux)
    .{ "-licuuc", "-licudata" }
else
    .{};

fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn expectSuccess(result: sio.Child.RunResult) !void {
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

// NOTE(Zig 0.17): `zig build-lib` cannot mix positional C sources with
// explicit `-M` modules, so the pthread shim is compiled first with
// `zig cc -c`, and the named "sio" import is mapped explicitly (the same
// shape as `zig build` uses for these modules).
fn buildRuntimeLib(
    allocator: std.mem.Allocator,
    runtime_source: []const u8,
    pthread_host_source: []const u8,
    swizzle_source: []const u8,
    sio_source: []const u8,
) !void {
    {
        const cc_argv = [_][]const u8{ "zig", "cc", "-c", pthread_host_source, "-o", "pthread_host.o" };
        const cc_result = try runCommand(allocator, cc_argv[0..]);
        defer allocator.free(cc_result.stdout);
        defer allocator.free(cc_result.stderr);
        try expectSuccess(cc_result);
    }
    {
        // The b64 swizzle kernel carries its own symbols (see build.zig
        // addB64SwizzleToModule); the child link needs its object too.
        const cc_argv = [_][]const u8{ "zig", "cc", "-c", swizzle_source, "-o", "sa_b64_swizzle.o" };
        const cc_result = try runCommand(allocator, cc_argv[0..]);
        defer allocator.free(cc_result.stdout);
        defer allocator.free(cc_result.stderr);
        try expectSuccess(cc_result);
    }
    const root_flag = try std.fmt.allocPrint(allocator, "-Mroot={s}", .{runtime_source});
    defer allocator.free(root_flag);
    const sio_flag = try std.fmt.allocPrint(allocator, "-Msio={s}", .{sio_source});
    defer allocator.free(sio_flag);
    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        "--dep",
        "sio",
        root_flag,
        sio_flag,
        "pthread_host.o",
        "sa_b64_swizzle.o",
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(allocator, build_lib_argv[0..]);
    defer allocator.free(build_lib_result.stdout);
    defer allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);
}

test "sa_term raw mode and winsize are usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const swizzle_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_b64_swizzle.c");
    defer std.testing.allocator.free(swizzle_source);
    const sio_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/sa_io.zig");
    defer std.testing.allocator.free(sio_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#define _GNU_SOURCE
        \\
        \\#include "sa_std.h"
        \\
        \\#include <fcntl.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <string.h>
        \\#include <sys/ioctl.h>
        \\#include <termios.h>
        \\#include <unistd.h>
        \\
        \\static int open_pty_pair(int *master, int *slave) {
        \\    char name[128];
        \\    int m = posix_openpt(O_RDWR | O_NOCTTY);
        \\    if (m < 0) return -1;
        \\    if (grantpt(m) != 0) return -1;
        \\    if (unlockpt(m) != 0) return -1;
        \\    if (ptsname_r(m, name, sizeof(name)) != 0) return -1;
        \\    int s = open(name, O_RDWR | O_NOCTTY);
        \\    if (s < 0) return -1;
        \\    *master = m;
        \\    *slave = s;
        \\    return 0;
        \\}
        \\
        \\static int termios_matches(const struct termios *before, const struct termios *after) {
        \\    if (before->c_iflag != after->c_iflag) return 0;
        \\    if (before->c_oflag != after->c_oflag) return 0;
        \\    if (before->c_cflag != after->c_cflag) return 0;
        \\    if (before->c_lflag != after->c_lflag) return 0;
        \\    if (before->c_line != after->c_line) return 0;
        \\    if (before->c_ispeed != after->c_ispeed) return 0;
        \\    if (before->c_ospeed != after->c_ospeed) return 0;
        \\    for (size_t i = 0; i < NCCS; ++i) {
        \\        if (before->c_cc[i] != after->c_cc[i]) return 0;
        \\    }
        \\    return 1;
        \\}
        \\
        \\int main(void) {
        \\    int master = -1;
        \\    int slave = -1;
        \\    struct termios before;
        \\    struct termios after;
        \\    struct winsize ws;
        \\    SaTermWinsize queried = {0};
        \\    uint64_t session = 0;
        \\
        \\    if (open_pty_pair(&master, &slave) != 0) return 2;
        \\    ws.ws_row = 24;
        \\    ws.ws_col = 80;
        \\    ws.ws_xpixel = 320;
        \\    ws.ws_ypixel = 200;
        \\    if (ioctl(slave, TIOCSWINSZ, &ws) != 0) return 3;
        \\    if (dup2(slave, STDIN_FILENO) < 0) return 4;
        \\    close(slave);
        \\    if (tcgetattr(STDIN_FILENO, &before) != 0) return 5;
        \\    if (sa_term_raw_enter(sa_io_stdin(), &session) != SA_STD_OK) return 6;
        \\    if (session == 0) return 7;
        \\    if (tcgetattr(STDIN_FILENO, &after) != 0) return 8;
        \\    if ((after.c_lflag & (ECHO | ICANON)) != 0) return 9;
        \\    if (after.c_cc[VMIN] != 1 || after.c_cc[VTIME] != 0) return 10;
        \\    if (sa_term_winsize(sa_io_stdin(), &queried) != SA_STD_OK) return 11;
        \\    if (queried.row != 24 || queried.col != 80) return 12;
        \\    if (queried.xpixel != 320 || queried.ypixel != 200) return 13;
        \\    if (sa_term_raw_leave(session) != SA_STD_OK) return 14;
        \\    if (tcgetattr(STDIN_FILENO, &after) != 0) return 15;
        \\    if (!termios_matches(&before, &after)) return 16;
        \\    close(master);
        \\    puts("term raw mode ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "raw_mode.c", c_source);

    try buildRuntimeLib(std.testing.allocator, runtime_source, pthread_host_source, swizzle_source, sio_source);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "raw_mode.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_term_raw_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_term_raw_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("term raw mode ok\n", run_result.stdout);
}

test "sa_term epoll and process streaming are usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const swizzle_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_b64_swizzle.c");
    defer std.testing.allocator.free(swizzle_source);
    const sio_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/sa_io.zig");
    defer std.testing.allocator.free(sio_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#define _GNU_SOURCE
        \\
        \\#include "sa_std.h"
        \\
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <sys/epoll.h>
        \\#include <unistd.h>
        \\
        \\int main(void) {
        \\    SaProcessArgv argv[2];
        \\    uint64_t process = 0;
        \\    uint64_t stdout_handle = 0;
        \\    uint64_t stderr_handle = 0;
        \\    uint64_t epoll_handle = 0;
        \\    SaTermEpollEvent events[4] = {{0}};
        \\    uint64_t event_count = 0;
        \\    uint32_t code = 0;
        \\    char buffer[64] = {0};
        \\    uint64_t read_count = 0;
        \\
        \\    argv[0].data = (const uint8_t *)"/bin/echo";
        \\    argv[0].len = 9;
        \\    argv[1].data = (const uint8_t *)"stream";
        \\    argv[1].len = 6;
        \\    if (sa_std_process_spawn_stream(argv, 2, &process, &stdout_handle, &stderr_handle) != SA_STD_OK) return 2;
        \\    if (process == 0 || stdout_handle == 0 || stderr_handle == 0) return 3;
        \\    if (sa_term_epoll_create(0, &epoll_handle) != SA_STD_OK) return 4;
        \\    if (sa_term_epoll_ctl(epoll_handle, EPOLL_CTL_ADD, stdout_handle, EPOLLIN, stdout_handle) != SA_STD_OK) return 5;
        \\    if (sa_term_epoll_wait(epoll_handle, events, 4, 2000, &event_count) != SA_STD_OK) return 6;
        \\    if (event_count == 0) return 7;
        \\    if (events[0].data != stdout_handle) return 8;
        \\    if ((events[0].events & (EPOLLIN | EPOLLHUP)) == 0) return 9;
        \\    if (sa_std_read(stdout_handle, (uint8_t *)buffer, sizeof(buffer), &read_count) != SA_STD_OK) return 10;
        \\    if (read_count == 0) return 11;
        \\    if (memcmp(buffer, "stream", 6) != 0) return 12;
        \\    if (sa_std_process_wait(process, &code) != SA_STD_OK) return 13;
        \\    if (code != 0) return 14;
        \\    if (sa_term_epoll_close(epoll_handle) != SA_STD_OK) return 15;
        \\    if (sa_std_close(stdout_handle) != SA_STD_OK) return 16;
        \\    if (sa_std_close(stderr_handle) != SA_STD_OK) return 17;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 18;
        \\    puts("term stream ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "stream.c", c_source);

    try buildRuntimeLib(std.testing.allocator, runtime_source, pthread_host_source, swizzle_source, sio_source);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "stream.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_term_stream_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_term_stream_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("term stream ok\n", run_result.stdout);
}
