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

fn expectSuccessCode(result: std.process.Child.RunResult) !void {
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "sa_std dynamic loading helpers are usable from C" {
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

    const plugin_source =
        \\pub const plugin_descriptor = extern struct {
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\};
        \\pub export var saasm_plugin_descriptor_v1: plugin_descriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_descriptor))),
        \\    .name = "plugin_smoke",
        \\};
    ;
    try writeSource(tmp.dir, "plugin_smoke.zig", plugin_source);

    const build_plugin_argv = [_][]const u8{ "zig", "build-lib", "plugin_smoke.zig", "-dynamic", "-O", "Debug", "-femit-bin=libplugin_smoke.so" };
    const build_plugin_result = try runCommand(std.testing.allocator, build_plugin_argv[0..]);
    defer std.testing.allocator.free(build_plugin_result.stdout);
    defer std.testing.allocator.free(build_plugin_result.stderr);
    try expectSuccess(build_plugin_result);

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\
        \\int main(void) {
        \\    const uint8_t path[] = "./libplugin_smoke.so";
        \\    const uint8_t symbol[] = "saasm_plugin_descriptor_v1";
        \\    uint64_t handle = 0;
        \\    void *ptr = 0;
        \\    if (sa_dl_open(path, sizeof(path) - 1, &handle) != SA_STD_OK) return 2;
        \\    if (handle == 0) return 3;
        \\    if (sa_dl_sym(handle, symbol, sizeof(symbol) - 1, &ptr) != SA_STD_OK) return 4;
        \\    if (ptr == 0) return 5;
        \\    if (sa_dl_close(handle) != SA_STD_OK) return 6;
        \\    return 0;
        \\}
    ;
    try writeSource(tmp.dir, "dl_smoke.c", c_source);

    const lib_dir = try original_cwd.realpathAlloc(std.testing.allocator, "zig-out/lib");
    defer std.testing.allocator.free(lib_dir);
    const rpath = try std.fmt.allocPrint(std.testing.allocator, "-Wl,-rpath,{s}", .{lib_dir});
    defer std.testing.allocator.free(rpath);
    const build_demo_argv = [_][]const u8{ "zig", "cc", "-I", include_dir, "dl_smoke.c", "-L", lib_dir, "-lsa_std", rpath, "-o", "sa_std_dl_demo" };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_dl_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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

test "sa_std detached pthread export runs without join" {
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

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
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
        "pthread_detached.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_pthread_detached_demo",
    };
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
        \\    const uint8_t json[] = "{\"name\":\"sci\",\"count\":7,\"active\":true,\"nested\":[1,2,3],\"schema\":{\"type\":\"object\"}}";
        \\    const uint8_t key_name[] = "name";
        \\    const uint8_t key_count[] = "count";
        \\    const uint8_t key_active[] = "active";
        \\    const uint8_t key_nested[] = "nested";
        \\    const uint8_t needle[] = "\"name\":\"sci\"";
        \\    uint64_t root = 0;
        \\    uint64_t child = 0;
        \\    uint64_t nested_item = 0;
        \\    uint64_t buffer = 0;
        \\    uint64_t writer = 0;
        \\    uint64_t writer_buffer = 0;
        \\    uint64_t count = 0;
        \\    int64_t first_nested_i64 = 0;
        \\    double count_f64 = 0.0;
        \\    int64_t count_i64 = 0;
        \\    int64_t count_i64_direct = 0;
        \\    double count_f64_direct = 0.0;
        \\    uint8_t active = 0;
        \\    uint8_t found = 0;
        \\    uint8_t writer_found = 0;
        \\    uint32_t kind = 0;
        \\    const uint8_t *name_ptr = NULL;
        \\    uint64_t name_len = 0;
        \\    const uint8_t *key_ptr = NULL;
        \\    uint64_t key_len = 0;
        \\    const uint8_t *json_text = NULL;
        \\    uint64_t json_len = 0;
        \\    const uint8_t *writer_text = NULL;
        \\    uint64_t writer_len = 0;
        \\    const uint8_t writer_prefix[] = "{\"name\":\"sci\",\"active\":true,\"count\":7,\"ratio\":";
        \\    const uint8_t writer_schema[] = "\"schema\":{\"type\":\"object\"}";
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
        \\    if (sa_json_object_get_string(root, key_name, sizeof(key_name) - 1, &name_ptr, &name_len) != SA_STD_OK) return 34;
        \\    if (name_ptr == NULL || name_len != 3 || memcmp(name_ptr, "sci", 3) != 0) return 35;
        \\
        \\    if (sa_json_object_get(root, key_count, sizeof(key_count) - 1, &child) != SA_STD_OK) return 9;
        \\    if (sa_json_as_f64(child, &count_f64) != SA_STD_OK) return 10;
        \\    if (sa_json_as_i64(child, &count_i64) != SA_STD_OK) return 11;
        \\    if (count_f64 != 7.0 || count_i64 != 7) return 12;
        \\    if (sa_json_free(child) != SA_STD_OK) return 13;
        \\    if (sa_json_object_get_i64(root, key_count, sizeof(key_count) - 1, &count_i64_direct) != SA_STD_OK) return 50;
        \\    if (sa_json_object_get_f64(root, key_count, sizeof(key_count) - 1, &count_f64_direct) != SA_STD_OK) return 51;
        \\    if (count_i64_direct != 7 || count_f64_direct != 7.0) return 52;
        \\
        \\    if (sa_json_object_get(root, key_active, sizeof(key_active) - 1, &child) != SA_STD_OK) return 14;
        \\    if (sa_json_as_bool(child, &active) != SA_STD_OK) return 15;
        \\    if (active != 1) return 16;
        \\    if (sa_json_free(child) != SA_STD_OK) return 17;
        \\    active = 0;
        \\    if (sa_json_object_get_bool(root, key_active, sizeof(key_active) - 1, &active) != SA_STD_OK) return 36;
        \\    if (active != 1) return 37;
        \\
        \\    if (sa_json_object_get(root, key_nested, sizeof(key_nested) - 1, &child) != SA_STD_OK) return 18;
        \\    if (sa_json_value_count(child, &count) != SA_STD_OK) return 19;
        \\    if (count != 3) return 20;
        \\    if (sa_json_array_get(child, 0, &nested_item) != SA_STD_OK) return 21;
        \\    if (sa_json_as_i64(nested_item, &first_nested_i64) != SA_STD_OK) return 22;
        \\    if (first_nested_i64 != 1) return 23;
        \\    if (sa_json_free(nested_item) != SA_STD_OK) return 24;
        \\    if (sa_json_free(child) != SA_STD_OK) return 25;
        \\
        \\    if (sa_json_object_key_at(root, 0, &key_ptr, &key_len) != SA_STD_OK) return 26;
        \\    if (key_ptr == NULL || key_len != 4 || memcmp(key_ptr, "name", 4) != 0) return 27;
        \\
        \\    if (sa_json_stringify(root, &buffer) != SA_STD_OK) return 28;
        \\    if (buffer == 0) return 29;
        \\    json_text = sa_json_buffer_data(buffer);
        \\    json_len = sa_json_buffer_len(buffer);
        \\    if (json_text == NULL || json_len == 0) return 30;
        \\    if (json_len < sizeof(needle) - 1) return 31;
        \\    for (uint64_t i = 0; i + (uint64_t)(sizeof(needle) - 1) <= json_len; ++i) {
        \\        if (memcmp(json_text + i, needle, sizeof(needle) - 1) == 0) {
        \\            found = 1;
        \\            break;
        \\        }
        \\    }
        \\    if (!found) return 31;
        \\    if (sa_json_buffer_free(buffer) != SA_STD_OK) return 32;
        \\
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 1, 0, 0, 0, &writer) != SA_STD_OK) return 38;
        \\    if (sa_json_writer_begin_object(writer) != SA_STD_OK) return 39;
        \\    if (sa_json_writer_field_string(writer, (const uint8_t *)"name", 4, (const uint8_t *)"sci", 3) != SA_STD_OK) return 53;
        \\    if (sa_json_writer_field_bool(writer, (const uint8_t *)"active", 6, 1) != SA_STD_OK) return 54;
        \\    if (sa_json_writer_field_i64(writer, (const uint8_t *)"count", 5, 7) != SA_STD_OK) return 55;
        \\    if (sa_json_writer_field_f64(writer, (const uint8_t *)"ratio", 5, 1.5) != SA_STD_OK) return 56;
        \\    if (sa_json_writer_field_null(writer, (const uint8_t *)"nothing", 7) != SA_STD_OK) return 57;
        \\    if (sa_json_object_get(root, (const uint8_t *)"schema", 6, &child) != SA_STD_OK) return 41;
        \\    if (sa_json_writer_field_node(writer, (const uint8_t *)"schema", 6, child) != SA_STD_OK) return 42;
        \\    if (sa_json_free(child) != SA_STD_OK) return 43;
        \\    if (sa_json_writer_end_object(writer) != SA_STD_OK) return 44;
        \\    if (sa_json_writer_finish(writer, &writer_buffer) != SA_STD_OK) return 45;
        \\    writer_text = sa_json_buffer_data(writer_buffer);
        \\    writer_len = sa_json_buffer_len(writer_buffer);
        \\    if (writer_text == NULL || writer_len < sizeof(writer_prefix) - 1) return 46;
        \\    if (memcmp(writer_text, writer_prefix, sizeof(writer_prefix) - 1) != 0) return 47;
        \\    for (uint64_t i = 0; i + (uint64_t)(sizeof(writer_schema) - 1) <= writer_len; ++i) {
        \\        if (memcmp(writer_text + i, writer_schema, sizeof(writer_schema) - 1) == 0) {
        \\            writer_found = 1;
        \\            break;
        \\        }
        \\    }
        \\    if (!writer_found) return 58;
        \\    if (sa_json_buffer_free(writer_buffer) != SA_STD_OK) return 48;
        \\    if (sa_json_writer_free(writer) != SA_STD_OK) return 49;
        \\
        \\    if (sa_json_free(root) != SA_STD_OK) return 33;
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
        "-lc",
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
        "-lc",
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
        "-lc",
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
        "-lc",
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

test "sa_std regex compile match and group access are usable from C" {
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

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
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
        "regex.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_regex_demo",
    };
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

test "sa_std json streaming handle exposes stable slices from C" {
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
        \\    const uint8_t json[] = "{\"name\":\"sci\",\"count\":7}";
        \\    uint64_t stream = 0;
        \\    uint32_t token = 0;
        \\    const uint8_t *slice = NULL;
        \\    uint64_t slice_len = 0;
        \\
        \\    stream = sa_json_stream_new(json, sizeof(json) - 1);
        \\    if (stream == 0) return 2;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_OBJECT_BEGIN) return 3;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 4;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 4 || memcmp(slice, "name", 4) != 0) return 5;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 6;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 3 || memcmp(slice, "sci", 3) != 0) return 7;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 8;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 5 || memcmp(slice, "count", 5) != 0) return 9;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_NUMBER) return 10;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 1 || memcmp(slice, "7", 1) != 0) return 11;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_OBJECT_END) return 12;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_END_OF_DOCUMENT) return 13;
        \\    if (sa_json_stream_free(stream) != SA_STD_OK) return 14;
        \\    puts("sa_std json stream ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json_stream_direct.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
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
        "json_stream_direct.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_json_stream_direct_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_stream_direct_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json stream ok"));
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
        "-lc",
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
        "-lc",
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

test "sa_std Deno facade runtime helpers are usable from C" {
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

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
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
        "deno_facade.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_facade_demo",
    };
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
