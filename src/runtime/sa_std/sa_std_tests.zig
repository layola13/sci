const std = @import("std");
const pthread = @import("pthread.zig");
const sa_std = @import("../sa_std.zig");
const AFT = @import("../sa_std.zig").AFT;
const IPPROTOT = @import("../sa_std.zig").IPPROTOT;
const PthreadHandle = @import("../sa_std.zig").PthreadHandle;
const SA_REGEX_EXTENDED = @import("../sa_std.zig").SA_REGEX_EXTENDED;
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_ALREADY_EXISTS = @import("../sa_std.zig").SA_STD_ERR_ALREADY_EXISTS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("../sa_std.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_PERMISSION_DENIED = @import("../sa_std.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_ERR_TRUNCATED = @import("../sa_std.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNKNOWN = @import("../sa_std.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_NET_POLL_MAX_HANDLES = @import("../sa_std.zig").SA_STD_NET_POLL_MAX_HANDLES;
const SA_STD_NET_POLL_READ = @import("../sa_std.zig").SA_STD_NET_POLL_READ;
const SA_STD_NET_POLL_WRITE = @import("../sa_std.zig").SA_STD_NET_POLL_WRITE;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SOCKT = @import("../sa_std.zig").SOCKT;
const SOLT = @import("../sa_std.zig").SOLT;
const SOT = @import("../sa_std.zig").SOT;
const SaProcessArgv = @import("../sa_std.zig").SaProcessArgv;
const allocPthreadHandle = @import("../sa_std.zig").allocPthreadHandle;
const applySigpipeIgnore = @import("../sa_std.zig").applySigpipeIgnore;
const buildInterfaceAddressesJson = @import("../sa_std.zig").buildInterfaceAddressesJson;
const builtin = @import("../sa_std.zig").builtin;
const ensureSocketHandle = @import("../sa_std.zig").ensureSocketHandle;
const expectTimeoutRoundedUpWithin = @import("../sa_std.zig").expectTimeoutRoundedUpWithin;
const fail = @import("../sa_std.zig").fail;
const freePthreadHandle = @import("../sa_std.zig").freePthreadHandle;
const getSocketOptBool = @import("../sa_std.zig").getSocketOptBool;
const getSocketOptInt = @import("../sa_std.zig").getSocketOptInt;
const getSocketOptTimeval = @import("../sa_std.zig").getSocketOptTimeval;
const hostBytes = @import("../sa_std.zig").hostBytes;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lxClose = @import("../sa_std.zig").lxClose;
const lxFcntl = @import("../sa_std.zig").lxFcntl;
const lxSocket = @import("../sa_std.zig").lxSocket;
const lxUnlink = @import("../sa_std.zig").lxUnlink;
const netErrorCodeName = @import("../sa_std.zig").netErrorCodeName;
const nsFromTimeval = @import("../sa_std.zig").nsFromTimeval;
const parseIp6FreebsdParts = @import("../sa_std.zig").parseIp6FreebsdParts;
const parseIpv6NumericFreebsd = @import("../sa_std.zig").parseIpv6NumericFreebsd;
const recv_msg_flag_pktinfo = @import("../sa_std.zig").recv_msg_flag_pktinfo;
const recv_msg_flag_timestamp = @import("../sa_std.zig").recv_msg_flag_timestamp;
const recv_multi_max_msgs = @import("../sa_std.zig").recv_multi_max_msgs;
const sa_b64dec_simd = @import("../sa_std.zig").sa_b64dec_simd;
const sa_crypto_random_bytes = @import("../sa_std.zig").sa_crypto_random_bytes;
const sa_deno_atob = @import("../sa_std.zig").sa_deno_atob;
const sa_deno_btoa = @import("../sa_std.zig").sa_deno_btoa;
const sa_deno_random_uuid = @import("../sa_std.zig").sa_deno_random_uuid;
const sa_fmt_buffer_data = @import("../sa_std.zig").sa_fmt_buffer_data;
const sa_fmt_buffer_free = @import("../sa_std.zig").sa_fmt_buffer_free;
const sa_fmt_buffer_len = @import("../sa_std.zig").sa_fmt_buffer_len;
const sa_fs_mkdir_p = @import("../sa_std.zig").sa_fs_mkdir_p;
const sa_hexdec_simd = @import("../sa_std.zig").sa_hexdec_simd;
const sa_hmac_sha1_hex = @import("../sa_std.zig").sa_hmac_sha1_hex;
const sa_hmac_sha256_hex = @import("../sa_std.zig").sa_hmac_sha256_hex;
const sa_mfind_u8 = @import("../sa_std.zig").sa_mfind_u8;
const sa_net_addr_family = @import("../sa_std.zig").sa_net_addr_family;
const sa_net_addr_free = @import("../sa_std.zig").sa_net_addr_free;
const sa_net_addr_host_len = @import("../sa_std.zig").sa_net_addr_host_len;
const sa_net_addr_port = @import("../sa_std.zig").sa_net_addr_port;
const sa_net_tcp_stream_peek = @import("../sa_std.zig").sa_net_tcp_stream_peek;
const sa_num_add_checked = @import("../sa_std.zig").sa_num_add_checked;
const sa_num_mul_checked = @import("../sa_std.zig").sa_num_mul_checked;
const sa_num_sub_checked = @import("../sa_std.zig").sa_num_sub_checked;
const sa_policy = @import("../sa_std.zig").sa_policy;
const sa_regex_buffer_data = @import("../sa_std.zig").sa_regex_buffer_data;
const sa_regex_buffer_free = @import("../sa_std.zig").sa_regex_buffer_free;
const sa_regex_buffer_len = @import("../sa_std.zig").sa_regex_buffer_len;
const sa_regex_compile = @import("../sa_std.zig").sa_regex_compile;
const sa_regex_free = @import("../sa_std.zig").sa_regex_free;
const sa_regex_group_len = @import("../sa_std.zig").sa_regex_group_len;
const sa_regex_group_ptr = @import("../sa_std.zig").sa_regex_group_ptr;
const sa_regex_group_start = @import("../sa_std.zig").sa_regex_group_start;
const sa_std_net_addr_reverse_lookup = @import("../sa_std.zig").sa_std_net_addr_reverse_lookup;
const sa_std_net_raw_socket = @import("../sa_std.zig").sa_std_net_raw_socket;
const sa_std_net_socket_getsockopt_int = @import("../sa_std.zig").sa_std_net_socket_getsockopt_int;
const sa_std_net_to_socket_addr_first = @import("../sa_std.zig").sa_std_net_to_socket_addr_first;
const sa_std_fs_open_create_excl = @import("../sa_std.zig").sa_std_fs_open_create_excl;
const sa_std_fs_open_read = @import("../sa_std.zig").sa_std_fs_open_read;
const sa_std_process_run = @import("../sa_std.zig").sa_std_process_run;
const sio = @import("../sa_std.zig").sio;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_net_poll_wait = @import("../sa_std.zig").sa_std_net_poll_wait;
const sa_std_net_tcp_accept = @import("../sa_std.zig").sa_std_net_tcp_accept;
const sa_std_net_tcp_connect = @import("../sa_std.zig").sa_std_net_tcp_connect;
const sa_std_net_tcp_listen = @import("../sa_std.zig").sa_std_net_tcp_listen;
const sa_std_net_tcp_stream_write = @import("../sa_std.zig").sa_std_net_tcp_stream_write;

test "net poll wait reports listener and stream readiness over loopback" {
    if (comptime is_wasm) return error.SkipZigTest;
    const host = "127.0.0.1";
    var listener: u64 = 0;
    var bound_port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener, &bound_port));
    defer _ = sa_std_close(listener);
    try std.testing.expect(bound_port != 0);

    var handles = [_]u64{listener};
    var interests = [_]u32{SA_STD_NET_POLL_READ};
    var ready = [_]u32{0};
    var ready_count: u64 = 99;

    // Nothing pending: a zero timeout returns immediately with no
    // ready entries, and a short timeout simply elapses.
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&handles, &interests, 1, 0, &ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 0), ready_count);
    try std.testing.expectEqual(@as(u32, 0), ready[0]);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&handles, &interests, 1, 25, &ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 0), ready_count);

    // A pending connection makes the listener readable.
    var client: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, bound_port, &client));
    defer _ = sa_std_close(client);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&handles, &interests, 1, 5000, &ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 1), ready_count);
    try std.testing.expect(ready[0] & SA_STD_NET_POLL_READ != 0);

    var server_side: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener, &server_side));
    defer _ = sa_std_close(server_side);

    // The accepted stream is writable at once and not readable
    // until the peer sends.
    handles[0] = server_side;
    interests[0] = SA_STD_NET_POLL_READ | SA_STD_NET_POLL_WRITE;
    ready[0] = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&handles, &interests, 1, 5000, &ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 1), ready_count);
    try std.testing.expect(ready[0] & SA_STD_NET_POLL_WRITE != 0);
    try std.testing.expect(ready[0] & SA_STD_NET_POLL_READ == 0);

    const msg = "poll-ping";
    var written: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_write(client, msg.ptr, msg.len, &written));
    try std.testing.expectEqual(@as(u64, msg.len), written);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&handles, &interests, 1, 5000, &ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 1), ready_count);
    try std.testing.expect(ready[0] & SA_STD_NET_POLL_READ != 0);

    // A wait over both sockets reports exactly the ready subset.
    var pair_handles = [_]u64{ listener, server_side };
    var pair_interests = [_]u32{ SA_STD_NET_POLL_READ, SA_STD_NET_POLL_READ };
    var pair_ready = [_]u32{ 0, 0 };
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_poll_wait(&pair_handles, &pair_interests, 2, 0, &pair_ready, &ready_count));
    try std.testing.expectEqual(@as(u64, 1), ready_count);
    try std.testing.expectEqual(@as(u32, 0), pair_ready[0]);
    try std.testing.expect(pair_ready[1] & SA_STD_NET_POLL_READ != 0);

    // Bad handles and oversized sets fail loudly.
    handles[0] = 0;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_poll_wait(&handles, &interests, 1, 0, &ready, &ready_count));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_poll_wait(&handles, &interests, SA_STD_NET_POLL_MAX_HANDLES + 1, 0, &ready, &ready_count));
}

test "DEF-R7: SIGPIPE ignored at startup; closed-pipe write surfaces BrokenPipe" {
    if (comptime is_wasm or builtin.os.tag != .linux) return error.SkipZigTest;
    // Apply directly (not the one-shot install): the unit runner
    // shuffles test order by seed, and peer tests may have installed
    // and later restored a different disposition before this test.
    applySigpipeIgnore();
    // The disposition itself is the policy: SIG_IGN, not a handler and
    // not SIG_DFL.
    var current: std.posix.Sigaction = undefined;
    std.posix.sigaction(std.posix.SIG.PIPE, null, &current);
    try std.testing.expectEqual(std.posix.SIG.IGN, current.handler.handler);
    // A write to a pipe with no readers must surface error.BrokenPipe
    // (mapped by callers to SA_STD_ERR_IO) — and the test process
    // surviving to evaluate this expectation is itself the assertion
    // that SIGPIPE did not kill it.
    var fds: [2]std.posix.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) return error.Unexpected;
    defer _ = std.c.close(fds[1]);
    _ = std.c.close(fds[0]);
    const rc = std.os.linux.write(fds[1], "x", 1);
    try std.testing.expectEqual(std.os.linux.E.PIPE, std.os.linux.errno(rc));
}

test "pthread handle registry reuses freed slots without a linear scan" {
    while (!pthread.pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    pthread.pthread_slots.clearRetainingCapacity();
    pthread.pthread_free_slots.clearRetainingCapacity();
    pthread.raw_pthread_owners.clearRetainingCapacity();
    pthread.pthread_registry_mutex.unlock();

    var first: PthreadHandle = undefined;
    var second: PthreadHandle = undefined;
    const first_handle = try allocPthreadHandle(&first);
    const second_handle = try allocPthreadHandle(&second);
    try std.testing.expectEqual(@as(i32, 1), first_handle);
    try std.testing.expectEqual(@as(i32, 2), second_handle);

    try std.testing.expectEqual(@as(*PthreadHandle, &first), try freePthreadHandle(first_handle));
    var replacement: PthreadHandle = undefined;
    const replacement_handle = try allocPthreadHandle(&replacement);
    try std.testing.expectEqual(first_handle, replacement_handle);

    while (!pthread.pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    pthread.pthread_slots.clearRetainingCapacity();
    pthread.pthread_free_slots.clearRetainingCapacity();
    pthread.raw_pthread_owners.clearRetainingCapacity();
    pthread.pthread_registry_mutex.unlock();
}

test "sa_fs_mkdir_p creates nested dirs, is idempotent, and rejects file paths" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}", .{&tmp.sub_path});
    defer alloc.free(base);
    const deep = try std.fmt.allocPrint(alloc, "{s}/a/b/c", .{base});
    defer alloc.free(deep);
    try std.testing.expectEqual(SA_STD_OK, sa_fs_mkdir_p(deep.ptr, @intCast(deep.len)));
    const stat = try sio.cwd().statFile(deep);
    try std.testing.expect(stat.kind == .directory);
    // Idempotent: a second call over existing directories succeeds.
    try std.testing.expectEqual(SA_STD_OK, sa_fs_mkdir_p(deep.ptr, @intCast(deep.len)));
    // An existing file as the final segment is ALREADY_EXISTS.
    const file_path = try std.fmt.allocPrint(alloc, "{s}/a/file.txt", .{base});
    defer alloc.free(file_path);
    {
        var f = try tmp.dir.createFile(std.testing.io, "a/file.txt", .{});
        f.close(std.testing.io);
    }
    try std.testing.expectEqual(SA_STD_ERR_ALREADY_EXISTS, sa_fs_mkdir_p(file_path.ptr, @intCast(file_path.len)));
    // A path through a file is an error, never a silent success.
    const through = try std.fmt.allocPrint(alloc, "{s}/a/file.txt/child", .{base});
    defer alloc.free(through);
    try std.testing.expect(sa_fs_mkdir_p(through.ptr, @intCast(through.len)) != SA_STD_OK);
}

test "sa_std_fs_open_create_excl: second create reports ALREADY_EXISTS" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/lock.txt", .{&tmp.sub_path});
    defer alloc.free(path);
    var handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_create_excl(path.ptr, @intCast(path.len), &handle));
    try std.testing.expect(handle != 0);
    try std.testing.expectEqual(SA_STD_OK, sa_std_close(handle));
    var second: u64 = 99;
    try std.testing.expectEqual(SA_STD_ERR_ALREADY_EXISTS, sa_std_fs_open_create_excl(path.ptr, @intCast(path.len), &second));
    try std.testing.expectEqual(@as(u64, 0), second);
}

test "policy gate intercepts fs open and process spawn at the std surface" {
    const allocator = std.testing.allocator;
    const policy = try sa_policy.parsePolicyJson(allocator, "{}");
    var ctx = sa_policy.PolicyContext.init(allocator, 42, policy);
    defer ctx.deinit(allocator);
    sa_policy.installContext(&ctx);
    defer sa_policy.clearContext();

    const path = "src/runtime/sa_policy.zig";
    var handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_PERMISSION_DENIED, sa_std_fs_open_read(path.ptr, path.len, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);

    const program = "/bin/true";
    const argv = [_]SaProcessArgv{.{ .data = program.ptr, .len = program.len }};
    var process_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_PERMISSION_DENIED, sa_std_process_run(&argv, argv.len, &process_handle));

    // Without a context the same calls go through (host enforces
    // "no policy, no start" at its own surface, not in the library).
    sa_policy.clearContext();
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_read(path.ptr, path.len, &handle));
    try std.testing.expect(handle != 0);
    _ = sa_std_close(handle);
}

test "num checked arithmetic returns exact results incl. boundaries" {
    // Normal cases.
    try std.testing.expectEqual(@as(i64, 42), sa_num_add_checked(40, 2));
    try std.testing.expectEqual(@as(i64, -1), sa_num_add_checked(-40, 39));
    try std.testing.expectEqual(@as(i64, 38), sa_num_sub_checked(40, 2));
    try std.testing.expectEqual(@as(i64, -42), sa_num_mul_checked(-6, 7));
    try std.testing.expectEqual(@as(i64, 0), sa_num_mul_checked(0, 0));
    // Boundary cases that must NOT trap.
    const max = std.math.maxInt(i64);
    const min = std.math.minInt(i64);
    try std.testing.expectEqual(max, sa_num_add_checked(max, 0));
    try std.testing.expectEqual(min, sa_num_add_checked(min, 0));
    try std.testing.expectEqual(max, sa_num_add_checked(max - 1, 1));
    try std.testing.expectEqual(min, sa_num_sub_checked(min, 0));
    try std.testing.expectEqual(max, sa_num_sub_checked(max, 0));
    try std.testing.expectEqual(@as(i64, 0), sa_num_sub_checked(min, min));
    try std.testing.expectEqual(min, sa_num_mul_checked(min, 1));
    try std.testing.expectEqual(max, sa_num_mul_checked(max, 1));
    try std.testing.expectEqual(@as(i64, -9223372036854775807), sa_num_mul_checked(max, -1));
    try std.testing.expectEqual(@as(i64, 0), sa_num_mul_checked(0, min));
    // Largest square that fits: 3037000499^2 < i64 max < 3037000500^2.
    try std.testing.expectEqual(@as(i64, 9223372030926249001), sa_num_mul_checked(3037000499, 3037000499));
    // Overflow cases trap by process abort (no wrapped value can be
    // observed); they are covered by the C probe in the delivery
    // evidence, not by in-process tests.
}

test "dns reverse lookup round-trips a resolved address" {
    const host = "127.0.0.1";
    var address: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_to_socket_addr_first(host.ptr, host.len, 80, &address));
    try std.testing.expect(address != 0);
    defer _ = sa_net_addr_free(address);

    // Length query first (hostname-style contract), then the real read.
    var needed: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_addr_reverse_lookup(address, null, 0, &needed));
    try std.testing.expect(needed > 0);
    var buf: [256]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_addr_reverse_lookup(address, &buf, buf.len, &out_len));
    try std.testing.expectEqual(needed, out_len);
    try std.testing.expectEqualStrings("localhost", buf[0..@intCast(out_len)]);

    // Contract errors.
    var dummy: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_addr_reverse_lookup(0, &buf, buf.len, &dummy));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_addr_reverse_lookup(address, &buf, buf.len, null));
}

test "raw socket creation validates shape and registers a datagram handle" {
    var handle: u64 = 0;
    // Shape validation happens before any syscall, so these hold in
    // every environment: bad domain, SOCK_STREAM, oversized protocol.
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_raw_socket(99, 3, 1, &handle));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_raw_socket(2, 1, 1, &handle));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_raw_socket(2, 3, 256, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);
    const status = sa_std_net_raw_socket(2, 3, 1, &handle);
    if (status == SA_STD_OK) {
        defer _ = sa_std_close(handle);
        try std.testing.expect(handle != 0);
        // SO_TYPE through the passthrough reads back SOCK_RAW (3).
        var value: i32 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_getsockopt_int(handle, 1, 3, &value));
        try std.testing.expectEqual(@as(i32, 3), value);
    } else {
        // Unprivileged environments may refuse raw sockets; the
        // refusal must be a loud status and never a fake handle.
        try std.testing.expectEqual(@as(u64, 0), handle);
        try std.testing.expect(status == SA_STD_ERR_ACCESS or status == SA_STD_ERR_PERMISSION_DENIED or status == SA_STD_ERR_UNSUPPORTED);
    }
    // The ping-socket form (SOCK_DGRAM + IPPROTO_ICMP) is admitted.
    var ping_handle: u64 = 0;
    const ping_status = sa_std_net_raw_socket(2, 2, 1, &ping_handle);
    if (ping_status == SA_STD_OK) {
        defer _ = sa_std_close(ping_handle);
        var value: i32 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_getsockopt_int(ping_handle, 1, 3, &value));
        try std.testing.expectEqual(@as(i32, 2), value);
    } else {
        try std.testing.expectEqual(@as(u64, 0), ping_handle);
    }
}
