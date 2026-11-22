const std = @import("std");
const sio = @import("sio");
const copyRuntimeArchiveToCwd = @import("helpers.zig").copyRuntimeArchiveToCwd;
const expectSuccess = @import("helpers.zig").expectSuccess;
const icu_demo_link_args = @import("helpers.zig").icu_demo_link_args;
const runCommand = @import("helpers.zig").runCommand;
const udpMulticastV6JoinPermitted = @import("helpers.zig").udpMulticastV6JoinPermitted;
const udpSendtoPermitted = @import("helpers.zig").udpSendtoPermitted;
const writeSource = @import("helpers.zig").writeSource;

test "sa_std udp loopback and address accessors are usable from C" {
    if (!udpSendtoPermitted()) return; // sandbox blocks sendto(2); nothing to verify
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
        \\#include <signal.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <sys/wait.h>
        \\#include <unistd.h>
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
        \\    if (sa_net_addr_free(recv_addr_handle).status != SA_STD_OK) return 15;
        \\    if (sa_net_addr_free(local_addr_handle).status != SA_STD_OK) return 16;
        \\    if (sa_net_udp_close(socket_handle) != SA_STD_OK) return 17;
        \\    puts("sa_std udp ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "udp.c", c_source);

    try copyRuntimeArchiveToCwd();

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
    } ++ icu_demo_link_args;
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

test "sa_std udp multicast helpers and scope id are usable from C" {
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
        \\
        \\int main(void) {
        \\    const uint8_t *bind_host = (const uint8_t *)"127.0.0.1";
        \\    const uint8_t *iface_host = (const uint8_t *)"0.0.0.0";
        \\    const uint8_t *group_host = (const uint8_t *)"224.0.0.251";
        \\#if SA_MCAST_V6
        \\    const uint8_t *bind_host_v6 = (const uint8_t *)"::1";
        \\    const uint8_t *group_host_v6 = (const uint8_t *)"ff01::114";
        \\#endif
        \\    const uint8_t multicast_if_v4[4] = {127, 0, 0, 1};
        \\    uint8_t multicast_if_v4_out[4] = {0, 0, 0, 0};
        \\    uint64_t socket_handle = 0;
        \\#if SA_MCAST_V6
        \\    uint64_t socket_handle_v6 = 0;
        \\#endif
        \\    uint64_t local_addr_handle = 0;
        \\#if SA_MCAST_V6
        \\    uint64_t local_addr_handle_v6 = 0;
        \\#endif
        \\    int32_t loop_enabled = -1;
        \\    uint32_t ttl = 0;
        \\
        \\    if (sa_std_net_udp_bind(bind_host, 9, 0, &socket_handle) != SA_STD_OK) return 2;
        \\    if (socket_handle == 0) return 3;
        \\    if (sa_std_net_udp_local_addr(socket_handle, &local_addr_handle) != SA_STD_OK) return 4;
        \\    if (local_addr_handle == 0) return 5;
        \\    if (sa_net_addr_scope_id(local_addr_handle) != 0) return 6;
        \\    if (sa_std_net_udp_set_multicast_loop_v4(socket_handle, 0) != SA_STD_OK) return 7;
        \\    if (sa_std_net_udp_multicast_loop_v4(socket_handle, &loop_enabled) != SA_STD_OK) return 8;
        \\    if (loop_enabled != 0) return 9;
        \\    if (sa_std_net_udp_set_multicast_loop_v4(socket_handle, 1) != SA_STD_OK) return 10;
        \\    if (sa_std_net_udp_multicast_loop_v4(socket_handle, &loop_enabled) != SA_STD_OK) return 11;
        \\    if (loop_enabled != 1) return 12;
        \\    if (sa_std_net_udp_set_multicast_ttl_v4(socket_handle, 7) != SA_STD_OK) return 13;
        \\    if (sa_std_net_udp_multicast_ttl_v4(socket_handle, &ttl) != SA_STD_OK) return 14;
        \\    if (ttl != 7) return 15;
        \\    if (sa_std_net_udp_set_multicast_if_v4(socket_handle, multicast_if_v4) != SA_STD_OK) return 16;
        \\    if (sa_std_net_udp_multicast_if_v4(socket_handle, multicast_if_v4_out) != SA_STD_OK) return 17;
        \\    if (multicast_if_v4_out[0] != 127 || multicast_if_v4_out[1] != 0 || multicast_if_v4_out[2] != 0 || multicast_if_v4_out[3] != 1) return 18;
        \\    if (sa_std_net_udp_join_multicast_v4(socket_handle, group_host, 11, iface_host, 7) != SA_STD_OK) return 19;
        \\    if (sa_std_net_udp_leave_multicast_v4(socket_handle, group_host, 11, iface_host, 7) != SA_STD_OK) return 20;
        \\#if SA_MCAST_V6
        \\    if (sa_std_net_udp_bind(bind_host_v6, 3, 0, &socket_handle_v6) != SA_STD_OK) return 21;
        \\    if (socket_handle_v6 == 0) return 22;
        \\    if (sa_std_net_udp_local_addr(socket_handle_v6, &local_addr_handle_v6) != SA_STD_OK) return 23;
        \\    if (local_addr_handle_v6 == 0) return 24;
        \\    if (sa_net_addr_scope_id(local_addr_handle_v6) != 0) return 25;
        \\    uint32_t multicast_if_v6 = 99;
        \\    if (sa_std_net_udp_set_multicast_if_v6(socket_handle_v6, 0) != SA_STD_OK) return 26;
        \\    if (sa_std_net_udp_multicast_if_v6(socket_handle_v6, &multicast_if_v6) != SA_STD_OK) return 27;
        \\    if (multicast_if_v6 != 0) return 28;
        \\    if (sa_std_net_udp_join_multicast_v6(socket_handle_v6, group_host_v6, 9, 0) != SA_STD_OK) return 29;
        \\    if (sa_std_net_udp_leave_multicast_v6(socket_handle_v6, group_host_v6, 9, 0) != SA_STD_OK) return 30;
        \\    if (sa_net_addr_free(local_addr_handle_v6).status != SA_STD_OK) return 31;
        \\    if (sa_net_udp_close(socket_handle_v6) != SA_STD_OK) return 32;
        \\#endif
        \\    if (sa_net_addr_free(local_addr_handle).status != SA_STD_OK) return 33;
        \\    if (sa_net_udp_close(socket_handle) != SA_STD_OK) return 34;
        \\    puts("sa_std udp multicast ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "udp_multicast.c", c_source);

    try copyRuntimeArchiveToCwd();

    var build_demo_argv = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer build_demo_argv.deinit();
    try build_demo_argv.appendSlice(&[_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "udp_multicast.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_udp_multicast_demo",
    });
    try build_demo_argv.appendSlice(&icu_demo_link_args);
    if (udpMulticastV6JoinPermitted()) try build_demo_argv.append("-DSA_MCAST_V6=1");
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv.items);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_udp_multicast_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std udp multicast ok"));
}

test "sa_std udp connected send and recv are usable from C" {
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
        \\    if (sa_net_addr_free(addr_b).status != SA_STD_OK) return 24;
        \\    if (sa_net_addr_free(addr_a).status != SA_STD_OK) return 25;
        \\    if (sa_net_udp_close(socket_b) != SA_STD_OK) return 26;
        \\    if (sa_net_udp_close(socket_a) != SA_STD_OK) return 27;
        \\    puts("sa_std udp connect ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "udp_connected.c", c_source);

    try copyRuntimeArchiveToCwd();

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
    } ++ icu_demo_link_args;
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

test "sa_std tcp stream peek does not consume bytes" {
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

    try copyRuntimeArchiveToCwd();

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
    } ++ icu_demo_link_args;
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
