const std = @import("std");

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
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

fn writeProcessArgv(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !struct { ptr: [*]const u8, len: u64, backing: [][]const u8 } {
    const backing = try allocator.alloc([]const u8, args.len);
    for (args, 0..) |arg, i| {
        backing[i] = try allocator.dupe(u8, arg);
    }
    return .{
        .ptr = @ptrCast(backing.ptr),
        .len = @as(u64, @intCast(backing.len)),
        .backing = backing,
    };
}

test "sa_std udp loopback and address accessors are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *bind_host = (const uint8_t *)"127.0.0.1";
        \\    const uint8_t *send_host = (const uint8_t *)"127.0.0.1";
        \\    const uint8_t payload[] = "udp-loopback";
        \\    uint64_t socket_handle = 0;
        \\    uint64_t recv_addr_handle = 0;
        \\    uint64_t local_addr_handle = 0;
        \\    uint64_t written = 0;
        \\    uint64_t read_count = 0;
        \\    uint8_t buffer[64] = {0};
        \\    const uint8_t *addr_host = 0;
        \\    uint64_t addr_host_len = 0;
        \\    uint16_t addr_port = 0;
        \\    uint32_t addr_family = 0;
        \\
        \\    if (sa_std_net_udp_bind(bind_host, 9, 0, &socket_handle) != SA_STD_OK) return 2;
        \\    if (socket_handle == 0) return 3;
        \\    if (sa_std_net_udp_local_addr(socket_handle, &local_addr_handle) != SA_STD_OK) return 4;
        \\    if (local_addr_handle == 0) return 5;
        \\    addr_port = sa_net_addr_port(local_addr_handle);
        \\    if (addr_port == 0) return 6;
        \\    if (sa_std_net_udp_send_to(socket_handle, payload, sizeof(payload) - 1, send_host, 9, addr_port, &written) != SA_STD_OK) return 7;
        \\    if (written != sizeof(payload) - 1) return 5;
        \\    if (sa_std_net_udp_recv_from(socket_handle, buffer, sizeof(buffer), &read_count, &recv_addr_handle) != SA_STD_OK) return 8;
        \\    if (read_count != sizeof(payload) - 1) return 9;
        \\    if (recv_addr_handle == 0) return 10;
        \\    addr_host = sa_net_addr_host(recv_addr_handle);
        \\    addr_host_len = sa_net_addr_host_len(recv_addr_handle);
        \\    addr_port = sa_net_addr_port(recv_addr_handle);
        \\    addr_family = sa_net_addr_family(recv_addr_handle);
        \\    if (addr_host == 0 || addr_host_len == 0) return 11;
        \\    if (memcmp(buffer, payload, sizeof(payload) - 1) != 0) return 12;
        \\    if (addr_port == 0) return 13;
        \\    if (addr_family != 2 && addr_family != 10) return 14;
        \\    if (sa_net_addr_free(recv_addr_handle) != SA_STD_OK) return 15;
        \\    if (sa_net_addr_free(local_addr_handle) != SA_STD_OK) return 16;
        \\    if (sa_net_udp_close(socket_handle) != SA_STD_OK) return 17;
        \\    puts("sa_std udp ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "udp.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "udp.c",
        "libsa_std.a",
        "-o",
        "sa_std_udp_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_udp_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std udp ok"));
}

test "sa_std udp connected send and recv are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *host = (const uint8_t *)"127.0.0.1";
        \\    const uint8_t payload_a[] = "udp-connected-a";
        \\    const uint8_t payload_b[] = "udp-connected-b";
        \\    uint64_t socket_a = 0;
        \\    uint64_t socket_b = 0;
        \\    uint64_t addr_a = 0;
        \\    uint64_t addr_b = 0;
        \\    uint64_t written = 0;
        \\    uint64_t read_count = 0;
        \\    uint16_t port_a = 0;
        \\    uint16_t port_b = 0;
        \\    uint32_t family_a = 0;
        \\    uint32_t family_b = 0;
        \\    uint8_t buffer[64] = {0};
        \\
        \\    if (sa_std_net_udp_bind(host, 9, 0, &socket_a) != SA_STD_OK) return 2;
        \\    if (socket_a == 0) return 3;
        \\    if (sa_std_net_udp_bind(host, 9, 0, &socket_b) != SA_STD_OK) return 4;
        \\    if (socket_b == 0) return 5;
        \\    if (sa_std_net_udp_local_addr(socket_a, &addr_a) != SA_STD_OK) return 6;
        \\    if (sa_std_net_udp_local_addr(socket_b, &addr_b) != SA_STD_OK) return 7;
        \\    if (addr_a == 0 || addr_b == 0) return 8;
        \\    port_a = sa_net_addr_port(addr_a);
        \\    port_b = sa_net_addr_port(addr_b);
        \\    family_a = sa_net_addr_family(addr_a);
        \\    family_b = sa_net_addr_family(addr_b);
        \\    if (port_a == 0 || port_b == 0) return 9;
        \\    if (family_a != 2 && family_a != 10) return 10;
        \\    if (family_b != 2 && family_b != 10) return 11;
        \\    if (sa_std_net_udp_connect(socket_a, host, 9, port_b) != SA_STD_OK) return 12;
        \\    if (sa_std_net_udp_connect(socket_b, host, 9, port_a) != SA_STD_OK) return 13;
        \\    if (sa_std_net_udp_send(socket_a, payload_a, sizeof(payload_a) - 1, &written) != SA_STD_OK) return 14;
        \\    if (written != sizeof(payload_a) - 1) return 15;
        \\    if (sa_std_net_udp_recv(socket_b, buffer, sizeof(buffer), &read_count) != SA_STD_OK) return 16;
        \\    if (read_count != sizeof(payload_a) - 1) return 17;
        \\    if (memcmp(buffer, payload_a, sizeof(payload_a) - 1) != 0) return 18;
        \\    if (sa_std_net_udp_send(socket_b, payload_b, sizeof(payload_b) - 1, &written) != SA_STD_OK) return 19;
        \\    if (written != sizeof(payload_b) - 1) return 20;
        \\    if (sa_std_net_udp_recv(socket_a, buffer, sizeof(buffer), &read_count) != SA_STD_OK) return 21;
        \\    if (read_count != sizeof(payload_b) - 1) return 22;
        \\    if (memcmp(buffer, payload_b, sizeof(payload_b) - 1) != 0) return 23;
        \\    if (sa_net_addr_free(addr_b) != SA_STD_OK) return 24;
        \\    if (sa_net_addr_free(addr_a) != SA_STD_OK) return 25;
        \\    if (sa_net_udp_close(socket_b) != SA_STD_OK) return 26;
        \\    if (sa_net_udp_close(socket_a) != SA_STD_OK) return 27;
        \\    puts("sa_std udp connect ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "udp_connected.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "udp_connected.c",
        "libsa_std.a",
        "-o",
        "sa_std_udp_connected_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_udp_connected_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std udp connect ok"));
}

test "sa_std static library exposes a usable C ABI" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *path = (const uint8_t *)"abi.txt";
        \\    const uint8_t *data = (const uint8_t *)"hello";
        \\    uint64_t handle = 0;
        \\    uint64_t count = 0;
        \\    uint8_t buffer[16] = {0};
        \\
        \\    if (sa_std_version() != SA_STD_ABI_VERSION) return 2;
        \\    if (sa_std_fs_open_write(path, 7, 1, &handle) != SA_STD_OK) return 3;
        \\    if (sa_std_write(handle, data, 5, &count) != SA_STD_OK || count != 5) return 4;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 5;
        \\
        \\    count = 0;
        \\    if (sa_std_fs_len(path, 7, &count) != SA_STD_OK || count != 5) return 6;
        \\    if (sa_std_fs_open_read(path, 7, &handle) != SA_STD_OK) return 7;
        \\    if (sa_std_read(handle, buffer, sizeof(buffer), &count) != SA_STD_OK || count != 5) return 8;
        \\    if (memcmp(buffer, data, 5) != 0) return 9;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 10;
        \\
        \\    count = 0;
        \\    if (sa_std_error_name(SA_STD_ERR_NOT_FOUND, buffer, sizeof(buffer), &count) != SA_STD_OK) return 11;
        \\    if (count != 9 || memcmp(buffer, "not_found", 9) != 0) return 12;
        \\    if (sa_std_fs_remove(path, 7) != SA_STD_OK) return 13;
        \\
        \\    puts("sa_std abi ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-o",
        "sa_std_c_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_c_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std abi ok\n", run_result.stdout);
}

test "sa_std tcp stream peek does not consume bytes" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <sys/wait.h>
        \\#include <unistd.h>
        \\
        \\int main(void) {
        \\    const uint8_t *host = (const uint8_t *)"127.0.0.1";
        \\    const uint8_t payload[] = "tcp-peek-data";
        \\    uint64_t listener = 0;
        \\    uint64_t server = 0;
        \\    uint64_t client = 0;
        \\    uint64_t written = 0;
        \\    uint64_t read_count = 0;
        \\    uint32_t port = 0;
        \\    uint8_t peek_buf[64] = {0};
        \\    uint8_t read_buf[64] = {0};
        \\    pid_t pid = 0;
        \\    int status = 0;
        \\
        \\    if (sa_std_net_tcp_listen(host, 9, 0, &listener, &port) != SA_STD_OK) return 2;
        \\    if (listener == 0 || port == 0) return 3;
        \\    pid = fork();
        \\    if (pid < 0) return 4;
        \\    if (pid == 0) {
        \\        if (sa_std_net_tcp_connect(host, 9, port, &client) != SA_STD_OK) _exit(20);
        \\        if (client == 0) _exit(21);
        \\        if (sa_std_write(client, payload, sizeof(payload) - 1, &written) != SA_STD_OK) _exit(22);
        \\        if (written != sizeof(payload) - 1) _exit(23);
        \\        if (sa_std_close(client) != SA_STD_OK) _exit(24);
        \\        _exit(0);
        \\    }
        \\    if (sa_std_net_tcp_accept(listener, &server) != SA_STD_OK) return 5;
        \\    if (server == 0) return 6;
        \\    if (sa_net_tcp_stream_peek(server, peek_buf, sizeof(peek_buf)) != (int32_t)(sizeof(payload) - 1)) return 7;
        \\    if (memcmp(peek_buf, payload, sizeof(payload) - 1) != 0) return 8;
        \\    if (sa_std_read(server, read_buf, sizeof(read_buf), &read_count) != SA_STD_OK) return 9;
        \\    if (read_count != sizeof(payload) - 1) return 10;
        \\    if (memcmp(read_buf, payload, sizeof(payload) - 1) != 0) return 11;
        \\    if (sa_net_tcp_stream_peek(server, peek_buf, sizeof(peek_buf)) != 0) return 12;
        \\    if (sa_std_close(server) != SA_STD_OK) return 13;
        \\    if (sa_std_close(listener) != SA_STD_OK) return 14;
        \\    if (waitpid(pid, &status, 0) < 0) return 15;
        \\    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return 16;
        \\    puts("sa_std tcp peek ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "tcp_peek.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "tcp_peek.c",
        "libsa_std.a",
        "-o",
        "sa_std_tcp_peek_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_tcp_peek_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std tcp peek ok"));
}

test "sa_std fmt and process exports are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
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
        \\
        \\    SaProcessArgv argv[2];
        \\    argv[0].data = (const uint8_t *)"/bin/echo";
        \\    argv[0].len = 9;
        \\    argv[1].data = (const uint8_t *)"sa_std_runtime";
        \\    argv[1].len = 14;
        \\    uint64_t process = 0;
        \\    uint32_t code = 0;
        \\    if (sa_std_process_run(argv, 2, &process) != SA_STD_OK) return 7;
        \\    if (process == 0) return 8;
        \\    if (sa_std_process_wait(process, &code) != SA_STD_OK) return 9;
        \\    if (code != 0) return 10;
        \\    if (sa_std_process_close(process) != SA_STD_OK) return 11;
        \\    puts("sa_std fmt/process ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-o",
        "sa_std_fmtdemo",
    };
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



test "sa_std json exports are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\
        \\#include <stdio.h>
        \\
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t json[] = "{\"name\":\"sci\",\"count\":7,\"active\":true,\"nested\":[1,2,3]}";
        \\    const uint8_t key_name[] = "name";
        \\    const uint8_t key_count[] = "count";
        \\    const uint8_t key_active[] = "active";
        \\    const uint8_t key_nested[] = "nested";
        \\    const uint8_t needle[] = "\"name\":\"sci\"";
        \\    uint64_t root = 0;
        \\    uint64_t child = 0;
        \\    uint64_t buffer = 0;
        \\    uint64_t count = 0;
        \\    double count_f64 = 0.0;
        \\    int64_t count_i64 = 0;
        \\    uint8_t active = 0;
        \\    uint8_t found = 0;
        \\    uint32_t kind = 0;
        \\    const uint8_t *name_ptr = NULL;
        \\    uint64_t name_len = 0;
        \\    const uint8_t *json_text = NULL;
        \\    uint64_t json_len = 0;
        \\
        \\    root = sa_json_parse(json, sizeof(json) - 1);
        \\    if (root == 0) return 2;
        \\    kind = sa_json_kind(root);
        \\    if (kind != SA_JSON_KIND_OBJECT) return 3;
        \\
        \\    if (sa_json_object_get(root, key_name, sizeof(key_name) - 1, &child) != SA_STD_OK) return 4;
        \\    if (child == 0) return 5;
        \\    kind = sa_json_kind(child);
        \\    if (kind != SA_JSON_KIND_STRING) return 6;
        \\    name_ptr = sa_json_string_ptr(child);
        \\    name_len = sa_json_string_len(child);
        \\    if (name_ptr == NULL || name_len != 3 || memcmp(name_ptr, "sci", 3) != 0) return 7;
        \\    if (sa_json_free(child) != SA_STD_OK) return 8;
        \\
        \\    if (sa_json_object_get(root, key_count, sizeof(key_count) - 1, &child) != SA_STD_OK) return 9;
        \\    if (sa_json_as_f64(child, &count_f64) != SA_STD_OK) return 10;
        \\    if (sa_json_as_i64(child, &count_i64) != SA_STD_OK) return 11;
        \\    if (count_f64 != 7.0 || count_i64 != 7) return 12;
        \\    if (sa_json_free(child) != SA_STD_OK) return 13;
        \\
        \\    if (sa_json_object_get(root, key_active, sizeof(key_active) - 1, &child) != SA_STD_OK) return 14;
        \\    if (sa_json_as_bool(child, &active) != SA_STD_OK) return 15;
        \\    if (active != 1) return 16;
        \\    if (sa_json_free(child) != SA_STD_OK) return 17;
        \\
        \\    if (sa_json_object_get(root, key_nested, sizeof(key_nested) - 1, &child) != SA_STD_OK) return 18;
        \\    if (sa_json_value_count(child, &count) != SA_STD_OK) return 19;
        \\    if (count != 3) return 20;
        \\    if (sa_json_free(child) != SA_STD_OK) return 21;
        \\
        \\    if (sa_json_stringify(root, &buffer) != SA_STD_OK) return 22;
        \\    if (buffer == 0) return 23;
        \\    json_text = sa_json_buffer_data(buffer);
        \\    json_len = sa_json_buffer_len(buffer);
        \\    if (json_text == NULL || json_len == 0) return 24;
        \\    if (json_len < sizeof(needle) - 1) return 25;
        \\    for (uint64_t i = 0; i + (uint64_t)(sizeof(needle) - 1) <= json_len; ++i) {
        \\        if (memcmp(json_text + i, needle, sizeof(needle) - 1) == 0) {
        \\            found = 1;
        \\            break;
        \\        }
        \\    }
        \\    if (!found) return 25;
        \\    if (sa_json_buffer_free(buffer) != SA_STD_OK) return 26;
        \\
        \\    if (sa_json_free(root) != SA_STD_OK) return 27;
        \\    puts("sa_std json ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "json.c",
        "libsa_std.a",
        "-o",
        "sa_std_json_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json ok"));
}

test "sa_std json streaming scanner and writer are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t chunk1[] = "{\"name\":\"s";
        \\    const uint8_t chunk2[] = "ci\",\"count\":";
        \\    const uint8_t chunk3[] = "7}";
        \\    uint64_t scanner = 0;
        \\    uint64_t writer = 0;
        \\    uint64_t buffer = 0;
        \\    SaJsonToken token = {0};
        \\    const uint8_t *json = NULL;
        \\    uint64_t json_len = 0;
        \\
        \\    if (sa_json_scanner_new(&scanner) != SA_STD_OK) return 2;
        \\    if (scanner == 0) return 3;
        \\    if (sa_json_scanner_feed(scanner, chunk1, sizeof(chunk1) - 1) != SA_STD_OK) return 4;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_OBJECT_BEGIN) return 5;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 4 || memcmp(token.text_ptr, "name", 4) != 0) return 6;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_PARTIAL_STRING || token.text_len != 1 || memcmp(token.text_ptr, "s", 1) != 0) return 7;
        \\    if (sa_json_scanner_feed(scanner, chunk2, sizeof(chunk2) - 1) != SA_STD_OK) return 8;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 2 || memcmp(token.text_ptr, "ci", 2) != 0) return 9;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 5 || memcmp(token.text_ptr, "count", 5) != 0) return 10;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_ERR_TRUNCATED) return 11;
        \\    if (sa_json_scanner_feed(scanner, chunk3, sizeof(chunk3) - 1) != SA_STD_OK) return 12;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_NUMBER || token.text_len != 1 || memcmp(token.text_ptr, "7", 1) != 0) return 13;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_OBJECT_END) return 14;
        \\    if (sa_json_scanner_end_input(scanner) != SA_STD_OK) return 15;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_END_OF_DOCUMENT) return 16;
        \\    if (sa_json_scanner_free(scanner) != SA_STD_OK) return 17;
        \\
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 1, 0, 0, 0, &writer) != SA_STD_OK) return 18;
        \\    if (writer == 0) return 19;
        \\    if (sa_json_writer_begin_object(writer) != SA_STD_OK) return 20;
        \\    if (sa_json_writer_object_field(writer, (const uint8_t *)"name", 4) != SA_STD_OK) return 21;
        \\    if (sa_json_writer_write_string(writer, (const uint8_t *)"sci", 3) != SA_STD_OK) return 22;
        \\    if (sa_json_writer_object_field(writer, (const uint8_t *)"count", 5) != SA_STD_OK) return 23;
        \\    if (sa_json_writer_write_i64(writer, 7) != SA_STD_OK) return 24;
        \\    if (sa_json_writer_end_object(writer) != SA_STD_OK) return 25;
        \\    if (sa_json_writer_finish(writer, &buffer) != SA_STD_OK) return 26;
        \\    if (buffer == 0) return 27;
        \\    json = sa_json_buffer_data(buffer);
        \\    json_len = sa_json_buffer_len(buffer);
        \\    if (json == NULL || json_len == 0) return 28;
        \\    if (memcmp(json, "{\"name\":\"sci\",\"count\":7}", json_len) != 0) return 29;
        \\    if (sa_json_writer_finish(writer, &buffer) != SA_STD_OK) return 30;
        \\    if (sa_json_buffer_free(buffer) != SA_STD_OK) return 31;
        \\    if (sa_json_writer_free(writer) != SA_STD_OK) return 32;
        \\    puts("sa_std json streaming ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json_stream.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "json_stream.c",
        "libsa_std.a",
        "-o",
        "sa_std_json_stream_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_stream_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json streaming ok"));
}

test "sa_std time exports are usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "time.c",
        "libsa_std.a",
        "-o",
        "sa_std_time_demo",
    };
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
