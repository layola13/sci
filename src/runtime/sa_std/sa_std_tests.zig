const std = @import("std");
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
const sa_regex_match_all = @import("../sa_std.zig").sa_regex_match_all;
const sa_regex_match_free = @import("../sa_std.zig").sa_regex_match_free;
const sa_regex_match_list_at = @import("../sa_std.zig").sa_regex_match_list_at;
const sa_regex_match_list_count = @import("../sa_std.zig").sa_regex_match_list_count;
const sa_regex_match_list_free = @import("../sa_std.zig").sa_regex_match_list_free;
const sa_regex_replace = @import("../sa_std.zig").sa_regex_replace;
const sa_regex_replace_all = @import("../sa_std.zig").sa_regex_replace_all;
const sa_regex_split = @import("../sa_std.zig").sa_regex_split;
const sa_regex_split_count = @import("../sa_std.zig").sa_regex_split_count;
const sa_regex_split_free = @import("../sa_std.zig").sa_regex_split_free;
const sa_regex_split_len = @import("../sa_std.zig").sa_regex_split_len;
const sa_regex_split_ptr = @import("../sa_std.zig").sa_regex_split_ptr;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_fs_file_write = @import("../sa_std.zig").sa_std_fs_file_write;
const sa_std_fs_open_create_excl = @import("../sa_std.zig").sa_std_fs_open_create_excl;
const sa_std_fs_open_read = @import("../sa_std.zig").sa_std_fs_open_read;
const sa_std_fs_open_write = @import("../sa_std.zig").sa_std_fs_open_write;
const sa_std_fs_remove = @import("../sa_std.zig").sa_std_fs_remove;
const sa_std_net_addr_reverse_lookup = @import("../sa_std.zig").sa_std_net_addr_reverse_lookup;
const sa_std_net_error_code_from_native_error = @import("../sa_std.zig").sa_std_net_error_code_from_native_error;
const sa_std_net_error_code_from_posix_errno = @import("../sa_std.zig").sa_std_net_error_code_from_posix_errno;
const sa_std_net_error_code_from_status = @import("../sa_std.zig").sa_std_net_error_code_from_status;
const sa_std_net_error_code_from_wsa_error = @import("../sa_std.zig").sa_std_net_error_code_from_wsa_error;
const sa_std_net_error_code_name = @import("../sa_std.zig").sa_std_net_error_code_name;
const sa_std_net_error_platform = @import("../sa_std.zig").sa_std_net_error_platform;
const sa_std_net_hostname = @import("../sa_std.zig").sa_std_net_hostname;
const sa_std_net_ja3_hash = @import("../sa_std.zig").sa_std_net_ja3_hash;
const sa_std_net_ja4_hash12 = @import("../sa_std.zig").sa_std_net_ja4_hash12;
const sa_std_net_poll_wait = @import("../sa_std.zig").sa_std_net_poll_wait;
const sa_std_net_raw_socket = @import("../sa_std.zig").sa_std_net_raw_socket;
const sa_std_net_sha256_hex = @import("../sa_std.zig").sa_std_net_sha256_hex;
const sa_std_net_socket_getsockopt = @import("../sa_std.zig").sa_std_net_socket_getsockopt;
const sa_std_net_socket_getsockopt_int = @import("../sa_std.zig").sa_std_net_socket_getsockopt_int;
const sa_std_net_socket_setsockopt = @import("../sa_std.zig").sa_std_net_socket_setsockopt;
const sa_std_net_socket_setsockopt_int = @import("../sa_std.zig").sa_std_net_socket_setsockopt_int;
const sa_std_net_tcp_accept = @import("../sa_std.zig").sa_std_net_tcp_accept;
const sa_std_net_tcp_accept_addr = @import("../sa_std.zig").sa_std_net_tcp_accept_addr;
const sa_std_net_tcp_connect = @import("../sa_std.zig").sa_std_net_tcp_connect;
const sa_std_net_tcp_connect_timeout = @import("../sa_std.zig").sa_std_net_tcp_connect_timeout;
const sa_std_net_tcp_connect_timeout_addr = @import("../sa_std.zig").sa_std_net_tcp_connect_timeout_addr;
const sa_std_net_tcp_listen = @import("../sa_std.zig").sa_std_net_tcp_listen;
const sa_std_net_tcp_listener_set_reuseaddr = @import("../sa_std.zig").sa_std_net_tcp_listener_set_reuseaddr;
const sa_std_net_tcp_listener_set_reuseport = @import("../sa_std.zig").sa_std_net_tcp_listener_set_reuseport;
const sa_std_net_tcp_stream_keepalive = @import("../sa_std.zig").sa_std_net_tcp_stream_keepalive;
const sa_std_net_tcp_stream_read = @import("../sa_std.zig").sa_std_net_tcp_stream_read;
const sa_std_net_tcp_stream_send_file = @import("../sa_std.zig").sa_std_net_tcp_stream_send_file;
const sa_std_net_tcp_stream_set_keepalive = @import("../sa_std.zig").sa_std_net_tcp_stream_set_keepalive;
const sa_std_net_tcp_stream_set_keepalive_params = @import("../sa_std.zig").sa_std_net_tcp_stream_set_keepalive_params;
const sa_std_net_tcp_stream_set_nodelay = @import("../sa_std.zig").sa_std_net_tcp_stream_set_nodelay;
const sa_std_net_tcp_stream_set_nonblocking = @import("../sa_std.zig").sa_std_net_tcp_stream_set_nonblocking;
const sa_std_net_tcp_stream_set_read_timeout = @import("../sa_std.zig").sa_std_net_tcp_stream_set_read_timeout;
const sa_std_net_tcp_stream_set_ttl = @import("../sa_std.zig").sa_std_net_tcp_stream_set_ttl;
const sa_std_net_tcp_stream_set_write_timeout = @import("../sa_std.zig").sa_std_net_tcp_stream_set_write_timeout;
const sa_std_net_tcp_stream_write = @import("../sa_std.zig").sa_std_net_tcp_stream_write;
const sa_std_net_to_socket_addr_first = @import("../sa_std.zig").sa_std_net_to_socket_addr_first;
const sa_std_net_to_socket_addr_list = @import("../sa_std.zig").sa_std_net_to_socket_addr_list;
const sa_std_net_udp_bind = @import("../sa_std.zig").sa_std_net_udp_bind;
const sa_std_net_udp_broadcast = @import("../sa_std.zig").sa_std_net_udp_broadcast;
const sa_std_net_udp_connect_addr = @import("../sa_std.zig").sa_std_net_udp_connect_addr;
const sa_std_net_udp_local_addr = @import("../sa_std.zig").sa_std_net_udp_local_addr;
const sa_std_net_udp_peer_addr = @import("../sa_std.zig").sa_std_net_udp_peer_addr;
const sa_std_net_udp_recv_msg = @import("../sa_std.zig").sa_std_net_udp_recv_msg;
const sa_std_net_udp_recv_multi = @import("../sa_std.zig").sa_std_net_udp_recv_multi;
const sa_std_net_udp_send = @import("../sa_std.zig").sa_std_net_udp_send;
const sa_std_net_udp_set_broadcast = @import("../sa_std.zig").sa_std_net_udp_set_broadcast;
const sa_std_net_udp_set_nonblocking = @import("../sa_std.zig").sa_std_net_udp_set_nonblocking;
const sa_std_net_udp_set_read_timeout = @import("../sa_std.zig").sa_std_net_udp_set_read_timeout;
const sa_std_net_udp_set_ttl = @import("../sa_std.zig").sa_std_net_udp_set_ttl;
const sa_std_net_udp_set_write_timeout = @import("../sa_std.zig").sa_std_net_udp_set_write_timeout;
const sa_std_net_unix_accept = @import("../sa_std.zig").sa_std_net_unix_accept;
const sa_std_net_unix_connect = @import("../sa_std.zig").sa_std_net_unix_connect;
const sa_std_net_unix_datagram_pair = @import("../sa_std.zig").sa_std_net_unix_datagram_pair;
const sa_std_net_unix_datagram_peer_cred = @import("../sa_std.zig").sa_std_net_unix_datagram_peer_cred;
const sa_std_net_unix_datagram_unbound = @import("../sa_std.zig").sa_std_net_unix_datagram_unbound;
const sa_std_net_unix_listen = @import("../sa_std.zig").sa_std_net_unix_listen;
const sa_std_process_run = @import("../sa_std.zig").sa_std_process_run;
const sa_unicode_normalize = @import("../sa_std.zig").sa_unicode_normalize;
const setSocketOptBool = @import("../sa_std.zig").setSocketOptBool;
const setSocketOptInt = @import("../sa_std.zig").setSocketOptInt;
const setSocketOptTimeval = @import("../sa_std.zig").setSocketOptTimeval;
const sio = @import("../sa_std.zig").sio;
const tcp_nodelay = @import("../sa_std.zig").tcp_nodelay;
const timevalFromNs = @import("../sa_std.zig").timevalFromNs;

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
    while (!sa_std.pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    sa_std.pthread_slots.clearRetainingCapacity();
    sa_std.pthread_free_slots.clearRetainingCapacity();
    sa_std.raw_pthread_owners.clearRetainingCapacity();
    sa_std.pthread_registry_mutex.unlock();

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

    while (!sa_std.pthread_registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    sa_std.pthread_slots.clearRetainingCapacity();
    sa_std.pthread_free_slots.clearRetainingCapacity();
    sa_std.raw_pthread_owners.clearRetainingCapacity();
    sa_std.pthread_registry_mutex.unlock();
}

test "runtime network host bytes reject embedded nul" {
    const bad = "127.0.0.1\x00.example";
    try std.testing.expectError(error.InvalidArgument, hostBytes(bad.ptr, bad.len));
    try std.testing.expectEqualStrings("127.0.0.1", try hostBytes("127.0.0.1".ptr, "127.0.0.1".len));
}

test "parseIpv6NumericFreebsd handles full, compressed and embedded forms" {
    const t = std.testing;
    try t.expectEqualSlices(u8, &std.mem.zeroes([16]u8), &parseIpv6NumericFreebsd("::").?);
    try t.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, &parseIpv6NumericFreebsd("::1").?);
    try t.expectEqualSlices(u8, &[_]u8{ 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8 }, &parseIpv6NumericFreebsd("1:2:3:4:5:6:7:8").?);
    try t.expectEqualSlices(u8, &[_]u8{ 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, &parseIpv6NumericFreebsd("fe80::1").?);
    try t.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 168, 0, 1 }, &parseIpv6NumericFreebsd("::ffff:192.168.0.1").?);
    try t.expect(parseIpv6NumericFreebsd("") == null);
    try t.expect(parseIpv6NumericFreebsd("1:2:3") == null);
    try t.expect(parseIpv6NumericFreebsd("1:2:3:4:5:6:7:8:9") == null);
    try t.expect(parseIpv6NumericFreebsd("1::2::3") == null);
    try t.expect(parseIpv6NumericFreebsd("1:2:3:4:5:6:7:8::") == null);
    try t.expect(parseIpv6NumericFreebsd("gggg::1") == null);
}

test "parseIp6FreebsdParts splits numeric scopes" {
    const t = std.testing;
    const p = parseIp6FreebsdParts("fe80::1%3").?;
    try t.expectEqual(@as(u32, 3), p.scope_id);
    try t.expectEqualSlices(u8, &[_]u8{ 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, &p.addr);
    try t.expect(parseIp6FreebsdParts("::1%") == null);
}

test "sa_hexdec_simd clean mixed-case roundtrips" {
    const hex = "0123456789abcdefABCDEF";
    var out: [11]u8 = undefined;
    const w = sa_hexdec_simd(hex.ptr, hex.len, &out);
    try std.testing.expectEqual(@as(u64, 11), w);
    const wn: usize = @intCast(w);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xAB, 0xCD, 0xEF }, out[0..wn]);
}

test "sa_hexdec_simd vector block then scalar tail" {
    // 64 clean chars exercise two vector iterations; 66 exercise tail.
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var out64: [32]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 32), sa_hexdec_simd(hex64.ptr, hex64.len, &out64));
    try std.testing.expectEqual(@as(u8, 0x01), out64[0]);
    try std.testing.expectEqual(@as(u8, 0xef), out64[31]);
    const hex66 = hex64 ++ "AB";
    var out66: [33]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 33), sa_hexdec_simd(hex66.ptr, hex66.len, &out66));
    try std.testing.expectEqual(@as(u8, 0xAB), out66[32]);
}

test "sa_hexdec_simd stops at invalid char and odd tail" {
    const bad = "00zz00";
    var out_bad: [3]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 1), sa_hexdec_simd(bad.ptr, bad.len, &out_bad));
    try std.testing.expectEqual(@as(u8, 0x00), out_bad[0]);
    // Invalid inside the second vector block falls back to scalar stop.
    const bad64 = "0123456789abcdef0123456789abcdef" ++ "zz" ++ "0123456789abcdef";
    var out_bad64: [34]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 16), sa_hexdec_simd(bad64.ptr, bad64.len, &out_bad64));
    const odd = "ABC";
    var out_odd: [2]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 1), sa_hexdec_simd(odd.ptr, odd.len, &out_odd));
    try std.testing.expectEqual(@as(u8, 0xAB), out_odd[0]);
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(null, 10, &out_odd));
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(odd.ptr, odd.len, null));
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(odd.ptr, 0, &out_odd));
}

test "sa_b64dec_simd clean alphabet roundtrips" {
    const txt = "ABCDabcd01236789";
    var out: [12]u8 = undefined;
    const w = sa_b64dec_simd(txt.ptr, txt.len, &out);
    try std.testing.expectEqual(@as(u64, 12), w);
    const wn: usize = @intCast(w);
    try std.testing.expectEqualSlices(u8, &.{ 0, 16, 131, 105, 183, 29, 211, 93, 183, 235, 191, 61 }, out[0..wn]);
}

test "sa_b64dec_simd vector width then invalid stop" {
    const clean64 = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
    var out64: [48]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 48), sa_b64dec_simd(clean64.ptr, clean64.len, &out64));
    try std.testing.expectEqual(@as(u8, 4), out64[0]);
    try std.testing.expectEqual(@as(u8, 16), out64[1]);
    try std.testing.expectEqual(@as(u8, 65), out64[2]);
    try std.testing.expectEqual(@as(u8, 65), out64[47]);
    const bad = "BBBB!!!!";
    var out_bad: [6]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 3), sa_b64dec_simd(bad.ptr, bad.len, &out_bad));
    const bad40 = ("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB") ++ "!!!!!!!!";
    var out_bad40: [30]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 24), sa_b64dec_simd(bad40.ptr, bad40.len, &out_bad40));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(null, 8, &out_bad));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(bad.ptr, bad.len, null));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(bad.ptr, 0, &out_bad));
}

test "sa_b64dec_simd avx2 block invalid rewinds to scalar" {
    // 128B input, invalid byte inside the first 64B vector block: the AVX2
    // path must stop before it (scalar re-decode), exactly like the
    // portable path (peer_b64mid shape, wider).
    var mid: [128]u8 = @splat(@as(u8, 'B'));
    mid[5] = '!';
    var out_mid: [96]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 3), sa_b64dec_simd(&mid, mid.len, &out_mid));
    try std.testing.expectEqual(@as(u8, 4), out_mid[0]);
    try std.testing.expectEqual(@as(u8, 16), out_mid[1]);
    try std.testing.expectEqual(@as(u8, 65), out_mid[2]);
    var clean128: [128]u8 = @splat(@as(u8, 'B'));
    var out128: [96]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 96), sa_b64dec_simd(&clean128, clean128.len, &out128));
    try std.testing.expectEqual(@as(u8, 65), out128[95]);
}

test "base64: sa_deno_btoa -> sa_deno_atob roundtrip via fmt buffer handles" {
    const data = "hello, sa_std!";
    const enc = sa_deno_btoa(data.ptr, data.len);
    try std.testing.expect(enc != 0);
    defer _ = sa_fmt_buffer_free(enc);
    const enc_ptr = sa_fmt_buffer_data(enc) orelse return error.TestUnexpectedResult;
    const enc_len = sa_fmt_buffer_len(enc);
    try std.testing.expectEqualStrings("aGVsbG8sIHNhX3N0ZCE=", enc_ptr[0..@intCast(enc_len)]);

    const dec = sa_deno_atob(enc_ptr, enc_len);
    try std.testing.expect(dec != 0);
    defer _ = sa_fmt_buffer_free(dec);
    const dec_ptr = sa_fmt_buffer_data(dec) orelse return error.TestUnexpectedResult;
    const dec_len = sa_fmt_buffer_len(dec);
    try std.testing.expectEqualStrings(data, dec_ptr[0..@intCast(dec_len)]);

    // Invalid input is an explicit 0 handle, never a partial decode.
    try std.testing.expectEqual(@as(u64, 0), sa_deno_atob("!!!".ptr, 3));
}

test "sa_mfind_u8 hit/miss/edges match memmem contract" {
    const hay = "abcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefgh";
    const hit0 = "abc";
    try std.testing.expectEqual(@as(u64, 0), sa_mfind_u8(hay.ptr, hay.len, hit0.ptr, hit0.len));
    const hitmid = "fgha";
    try std.testing.expectEqual(@as(u64, 5), sa_mfind_u8(hay.ptr, hay.len, hitmid.ptr, hitmid.len));
    const miss = "zzzzzzzz";
    try std.testing.expectEqual(@as(u64, hay.len), sa_mfind_u8(hay.ptr, hay.len, miss.ptr, miss.len));
    const empty = "";
    try std.testing.expectEqual(@as(u64, 0), sa_mfind_u8(hay.ptr, hay.len, empty.ptr, empty.len));
    const toolong = "abcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefgh";
    try std.testing.expectEqual(@as(u64, hay.len), sa_mfind_u8(hay.ptr, hay.len, toolong.ptr, toolong.len));
    var one: [1]u8 = .{0xFF};
    try std.testing.expectEqual(@as(u64, 8), sa_mfind_u8(null, 8, &one, 1));
    try std.testing.expectEqual(@as(u64, 8), sa_mfind_u8(hay.ptr, 8, null, 1));
}

test "net interface addresses json: snapshot contains loopback" {
    const bytes = try buildInterfaceAddressesJson(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(bytes.len >= 2);
    try std.testing.expectEqual(@as(u8, '['), bytes[0]);
    try std.testing.expectEqual(@as(u8, ']'), bytes[bytes.len - 1]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"name\":\"lo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"address\":\"127.0.0.1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"prefix_len\":8") != null);
}

test "unicode: normalize NFC/NFD/NFKC/NFKD vectors (JS oracle)" {
    const Case = struct { input: []const u8, form: i32, expected: []const u8 };
    const cases = [_]Case{
        .{ .input = "e\u{301}", .form = 0, .expected = "\u{e9}" },
        .{ .input = "e\u{301}", .form = 1, .expected = "e\u{301}" },
        .{ .input = "\u{e9}", .form = 1, .expected = "e\u{301}" },
        .{ .input = "\u{fb01}", .form = 3, .expected = "fi" },
        .{ .input = "\u{fb01}", .form = 2, .expected = "fi" },
        .{ .input = "\u{fb01}", .form = 0, .expected = "\u{fb01}" },
        .{ .input = "\u{b2}", .form = 3, .expected = "2" },
        .{ .input = "\u{b2}", .form = 0, .expected = "\u{b2}" },
        .{ .input = "\u{1100}\u{1161}", .form = 0, .expected = "\u{ac00}" },
        .{ .input = "\u{ac00}", .form = 1, .expected = "\u{1100}\u{1161}" },
        .{ .input = "\u{c5}", .form = 1, .expected = "A\u{30a}" },
        .{ .input = "\u{2126}", .form = 0, .expected = "\u{3a9}" },
        .{ .input = "", .form = 0, .expected = "" },
        .{ .input = "hello", .form = 3, .expected = "hello" },
        .{ .input = "caf\u{e9}", .form = 1, .expected = "cafe\u{301}" },
    };
    for (cases) |c| {
        const n = sa_unicode_normalize(c.input.ptr, c.input.len, c.form, null, 0);
        try std.testing.expectEqual(@as(i64, @intCast(c.expected.len)), n);
        var buf: [256]u8 = undefined;
        const m = sa_unicode_normalize(c.input.ptr, c.input.len, c.form, &buf, buf.len);
        try std.testing.expectEqual(@as(i64, @intCast(c.expected.len)), m);
        try std.testing.expectEqualStrings(c.expected, buf[0..@intCast(m)]);
    }
}

test "unicode: exact-fit buffers succeed (terminator warning is not failure)" {
    // Input exact fit: "hello" is 5 UTF-8 bytes -> 5 UTF-16 units in a
    // 5-unit buffer (ICU sets -124, content correct). Fill exact fit: a
    // 5-byte output buffer for a 5-byte result (same warning, must succeed).
    const input = "hello";
    const n = sa_unicode_normalize(input.ptr, input.len, 0, null, 0);
    try std.testing.expectEqual(@as(i64, 5), n);
    var buf: [5]u8 = undefined;
    const m = sa_unicode_normalize(input.ptr, input.len, 0, &buf, buf.len);
    try std.testing.expectEqual(@as(i64, 5), m);
    try std.testing.expectEqualStrings("hello", buf[0..@intCast(m)]);
}

test "unicode: small output buffer reports needed length without writing" {
    const input = "e\u{301}";
    var buf: [1]u8 = .{0xAA};
    const n = sa_unicode_normalize(input.ptr, input.len, 0, &buf, buf.len);
    try std.testing.expectEqual(@as(i64, 2), n);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[0]);
}

test "regex: replace expands group references" {
    const pat: []const u8 = "([a-z]+)@([a-z]+)";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);

    const text: []const u8 = "user@host";
    const repl: []const u8 = "$2/$1";
    const buf = sa_regex_replace(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    const out = sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))];
    try std.testing.expectEqualStrings("host/user", out);

    // $& whole match, $$ literal dollar, $` prefix, $' suffix, and an
    // out-of-range $9 that must stay literal.
    const text2: []const u8 = "x user@host y";
    const repl2: []const u8 = "[$&|$$|$`|$'|$9]";
    const buf2 = sa_regex_replace(re, text2.ptr, text2.len, repl2.ptr, repl2.len);
    try std.testing.expect(buf2 != 0);
    defer _ = sa_regex_buffer_free(buf2);
    const out2 = sa_regex_buffer_data(buf2).?[0..@intCast(sa_regex_buffer_len(buf2))];
    try std.testing.expectEqualStrings("x [user@host|$|x | y|$9] y", out2);
}

test "regex: replace is first-only and replace_all is global" {
    const pat: []const u8 = "([a-z])([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1 b2";
    const repl: []const u8 = "$2$1";

    const buf = sa_regex_replace(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    try std.testing.expectEqualStrings("1a b2", sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))]);

    const buf2 = sa_regex_replace_all(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf2 != 0);
    defer _ = sa_regex_buffer_free(buf2);
    try std.testing.expectEqualStrings("1a 2b", sa_regex_buffer_data(buf2).?[0..@intCast(sa_regex_buffer_len(buf2))]);

    const plain: []const u8 = "zz";
    const buf3 = sa_regex_replace_all(re, plain.ptr, plain.len, repl.ptr, repl.len);
    try std.testing.expect(buf3 != 0);
    defer _ = sa_regex_buffer_free(buf3);
    try std.testing.expectEqualStrings("zz", sa_regex_buffer_data(buf3).?[0..@intCast(sa_regex_buffer_len(buf3))]);
}

test "regex: replace_all expands empty matches like the JS global loop" {
    const pat: []const u8 = "x*";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "ab";
    const repl: []const u8 = "-";
    const buf = sa_regex_replace_all(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    try std.testing.expectEqualStrings("-a-b-", sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))]);
}

test "regex: match_all collects matches with capture groups" {
    const pat: []const u8 = "([a-z])([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1 b2 c";
    const list = sa_regex_match_all(re, text.ptr, text.len);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_match_list_free(list);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_match_list_count(list));

    const m0 = sa_regex_match_list_at(list, 0);
    try std.testing.expect(m0 != 0);
    defer _ = sa_regex_match_free(m0);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_start(m0, 0));
    try std.testing.expectEqualStrings("a1", sa_regex_group_ptr(m0, 0).?[0..@intCast(sa_regex_group_len(m0, 0))]);
    try std.testing.expectEqualStrings("a", sa_regex_group_ptr(m0, 1).?[0..@intCast(sa_regex_group_len(m0, 1))]);
    try std.testing.expectEqualStrings("1", sa_regex_group_ptr(m0, 2).?[0..@intCast(sa_regex_group_len(m0, 2))]);

    const m1 = sa_regex_match_list_at(list, 1);
    try std.testing.expect(m1 != 0);
    defer _ = sa_regex_match_free(m1);
    try std.testing.expectEqual(@as(u64, 3), sa_regex_group_start(m1, 0));
    try std.testing.expectEqualStrings("b2", sa_regex_group_ptr(m1, 0).?[0..@intCast(sa_regex_group_len(m1, 0))]);

    try std.testing.expectEqual(@as(u64, 0), sa_regex_match_list_at(list, 2));
}

test "regex: match_all reports the trailing empty match" {
    const pat: []const u8 = "a*";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "b";
    const list = sa_regex_match_all(re, text.ptr, text.len);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_match_list_free(list);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_match_list_count(list));
    const m0 = sa_regex_match_list_at(list, 0);
    try std.testing.expect(m0 != 0);
    defer _ = sa_regex_match_free(m0);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_start(m0, 0));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_len(m0, 0));
    const m1 = sa_regex_match_list_at(list, 1);
    try std.testing.expect(m1 != 0);
    defer _ = sa_regex_match_free(m1);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_group_start(m1, 0));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_len(m1, 0));
}

test "regex: split leading trailing and consecutive separators" {
    const pat: []const u8 = ",";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);

    const text: []const u8 = "a,,b,";
    const list = sa_regex_split(re, text.ptr, text.len, 0);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_split_free(list);
    try std.testing.expectEqual(@as(u64, 4), sa_regex_split_count(list));
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list, 0).?[0..@intCast(sa_regex_split_len(list, 0))]);
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list, 1).?[0..@intCast(sa_regex_split_len(list, 1))]);
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list, 2).?[0..@intCast(sa_regex_split_len(list, 2))]);
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list, 3).?[0..@intCast(sa_regex_split_len(list, 3))]);

    const text2: []const u8 = ",a";
    const list2 = sa_regex_split(re, text2.ptr, text2.len, 0);
    try std.testing.expect(list2 != 0);
    defer _ = sa_regex_split_free(list2);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_split_count(list2));
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list2, 0).?[0..@intCast(sa_regex_split_len(list2, 0))]);
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list2, 1).?[0..@intCast(sa_regex_split_len(list2, 1))]);

    const text3: []const u8 = "abc";
    const list3 = sa_regex_split(re, text3.ptr, text3.len, 0);
    try std.testing.expect(list3 != 0);
    defer _ = sa_regex_split_free(list3);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_split_count(list3));
    try std.testing.expectEqualStrings("abc", sa_regex_split_ptr(list3, 0).?[0..@intCast(sa_regex_split_len(list3, 0))]);

    const empty: []const u8 = "";
    const list4 = sa_regex_split(re, empty.ptr, empty.len, 0);
    try std.testing.expect(list4 != 0);
    defer _ = sa_regex_split_free(list4);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_split_count(list4));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_split_len(list4, 0));
}

test "regex: split inserts capture groups and honors limit" {
    const pat: []const u8 = "([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1b2c";

    const list = sa_regex_split(re, text.ptr, text.len, 0);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_split_free(list);
    try std.testing.expectEqual(@as(u64, 5), sa_regex_split_count(list));
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list, 0).?[0..@intCast(sa_regex_split_len(list, 0))]);
    try std.testing.expectEqualStrings("1", sa_regex_split_ptr(list, 1).?[0..@intCast(sa_regex_split_len(list, 1))]);
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list, 2).?[0..@intCast(sa_regex_split_len(list, 2))]);
    try std.testing.expectEqualStrings("2", sa_regex_split_ptr(list, 3).?[0..@intCast(sa_regex_split_len(list, 3))]);
    try std.testing.expectEqualStrings("c", sa_regex_split_ptr(list, 4).?[0..@intCast(sa_regex_split_len(list, 4))]);

    const list2 = sa_regex_split(re, text.ptr, text.len, 3);
    try std.testing.expect(list2 != 0);
    defer _ = sa_regex_split_free(list2);
    try std.testing.expectEqual(@as(u64, 3), sa_regex_split_count(list2));
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list2, 2).?[0..@intCast(sa_regex_split_len(list2, 2))]);

    // Empty input whose pattern matches at 0 splits to zero pieces (JS).
    const pat2: []const u8 = "a*";
    const re2 = sa_regex_compile(pat2.ptr, pat2.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re2 != 0);
    defer _ = sa_regex_free(re2);
    const empty: []const u8 = "";
    const list3 = sa_regex_split(re2, empty.ptr, empty.len, 0);
    try std.testing.expect(list3 != 0);
    defer _ = sa_regex_split_free(list3);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_split_count(list3));
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

test "ja3 hash matches reference md5 vector" {
    // Reference JA3 string and its canonical md5 (ja3er / Salesforce reference).
    const ja3 = "769,47-53-5-10-49161-49162-49171-49172-50-56-19-4,0-10-11,23-24-25,0";
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_ja3_hash(ja3.ptr, ja3.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 32), out_len);
    try std.testing.expectEqualStrings("ada70206e40642a3e4461f35503241d5", out[0..32]);
}

test "sha256 hex and ja4 truncation match" {
    // sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_sha256_hex("", 0, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 64), out_len);
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", out[0..64]);

    // JA4 12-char truncation is the first 12 hex chars of the same digest.
    var out12: [12]u8 = undefined;
    var len12: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_ja4_hash12("", 0, &out12, out12.len, &len12));
    try std.testing.expectEqual(@as(u64, 12), len12);
    try std.testing.expectEqualStrings("e3b0c4429 8fc"[0..0] ++ "e3b0c44298fc", out12[0..12]);
}

test "ja3/ja4 reject too-small output buffers" {
    var small: [8]u8 = undefined;
    var n: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_ja3_hash("x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_sha256_hex("x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_ja4_hash12("x", 1, &small, small.len, &n));
}

test "hmac sha256 matches RFC 4231 vectors" {
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;

    // Test Case 1: key = 0x0b x 20, data = "Hi There".
    const key1: [20]u8 = @splat(0x0b);
    const data1 = "Hi There";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(&key1, key1.len, data1.ptr, data1.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 64), out_len);
    try std.testing.expectEqualStrings("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", out[0..64]);

    // Test Case 2: key = "Jefe", data = "what do ya want for nothing?".
    const key2 = "Jefe";
    const data2 = "what do ya want for nothing?";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(key2.ptr, key2.len, data2.ptr, data2.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", out[0..64]);

    // Test Case 6: key = 0xaa x 131 (longer than the 64-byte block size,
    // so the key itself is hashed first).
    const key6: [131]u8 = @splat(0xaa);
    const data6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(&key6, key6.len, data6.ptr, data6.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", out[0..64]);
}

test "hmac sha1 matches RFC 2202 vectors" {
    var out: [40]u8 = undefined;
    var out_len: u64 = 0;

    // Case 1: key = 0x0b x 20, data = "Hi There".
    const key1: [20]u8 = @splat(0x0b);
    const data1 = "Hi There";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(&key1, key1.len, data1.ptr, data1.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 40), out_len);
    try std.testing.expectEqualStrings("b617318655057264e28bc0b6fb378c8ef146be00", out[0..40]);

    // Case 2: key = "Jefe", data = "what do ya want for nothing?".
    const key2 = "Jefe";
    const data2 = "what do ya want for nothing?";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(key2.ptr, key2.len, data2.ptr, data2.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", out[0..40]);

    // Case 6: key = 0xaa x 80 (longer than the 64-byte block size).
    const key6: [80]u8 = @splat(0xaa);
    const data6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(&key6, key6.len, data6.ptr, data6.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("aa4ae5e15272d00e95705637ce8a3b55ed402112", out[0..40]);
}

test "hmac hex rejects too-small output buffers" {
    var small: [16]u8 = undefined;
    var n: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_hmac_sha256_hex("k", 1, "x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_hmac_sha1_hex("k", 1, "x", 1, &small, small.len, &n));
}

test "crypto random bytes fills the caller buffer" {
    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(&a, a.len));
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(&b, b.len));
    // Two independent 32-byte draws colliding has probability 2^-256.
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_crypto_random_bytes(null, 4));
}

test "deno random uuid returns well-formed v4 text" {
    const h1 = sa_deno_random_uuid();
    try std.testing.expect(h1 != 0);
    defer _ = sa_fmt_buffer_free(h1);
    const data = sa_fmt_buffer_data(h1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 36), sa_fmt_buffer_len(h1));
    const text = data[0..36];
    // RFC 4122 layout: 8-4-4-4-12 lowercase hex, version 4, variant 10xx.
    try std.testing.expect(text[8] == '-' and text[13] == '-' and text[18] == '-' and text[23] == '-');
    try std.testing.expect(text[14] == '4');
    try std.testing.expect(text[19] == '8' or text[19] == '9' or text[19] == 'a' or text[19] == 'b');
    for (text, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) continue;
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
    const h2 = sa_deno_random_uuid();
    try std.testing.expect(h2 != 0);
    defer _ = sa_fmt_buffer_free(h2);
    const data2 = sa_fmt_buffer_data(h2) orelse return error.TestUnexpectedResult;
    try std.testing.expect(!std.mem.eql(u8, text, data2[0..36]));
}

test "socket helper round trip on raw udp socket" {
    const fd = try lxSocket(AFT.INET, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP);
    defer lxClose(fd);

    try setSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST, true);
    try std.testing.expect(try getSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST));
    try setSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST, false);
    try std.testing.expect(!(try getSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST)));

    try setSocketOptInt(fd, IPPROTOT.IP, std.posix.IP.TTL, 64);
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(fd, IPPROTOT.IP, std.posix.IP.TTL));

    const timeout_ns: u64 = 1_234_567_890;
    try setSocketOptTimeval(fd, SOLT.SOCKET, SOT.RCVTIMEO, timeout_ns);
    try expectTimeoutRoundedUpWithin(timeout_ns, try getSocketOptTimeval(fd, SOLT.SOCKET, SOT.RCVTIMEO));

    const tv = try timevalFromNs(timeout_ns);
    try std.testing.expectEqual(@as(u64, 1_234_567_000), try nsFromTimeval(tv));
}

test "generic sockopt passthrough updates live udp handle" {
    const host = "127.0.0.1";
    var handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &handle));
    defer _ = sa_std_close(handle);

    // SOL_SOCKET (1) / SO_BROADCAST (6) through the int convenience form.
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_setsockopt_int(handle, 1, 6, 1));
    var value: i32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_getsockopt_int(handle, 1, 6, &value));
    try std.testing.expectEqual(@as(i32, 1), value);

    // Byte form: SO_TYPE (3) reads back SOCK_DGRAM (2) as raw bytes.
    var raw: [4]u8 = .{ 0, 0, 0, 0 };
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_getsockopt(handle, 1, 3, &raw, raw.len, &out_len));
    try std.testing.expectEqual(@as(u64, 4), out_len);
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, &raw, .little));

    // Byte-form write, cross-checked through the dedicated getter.
    var on: [4]u8 = .{ 1, 0, 0, 0 };
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_setsockopt(handle, 1, 6, &on, on.len));
    var dedicated: i32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_broadcast(handle, &dedicated));
    try std.testing.expectEqual(@as(i32, 1), dedicated);

    // A bad level and a non-socket handle both fail loudly.
    try std.testing.expect(sa_std_net_socket_setsockopt_int(handle, 9999, 6, 1) != SA_STD_OK);
    try std.testing.expect(sa_std_net_socket_setsockopt_int(0, 1, 6, 1) != SA_STD_OK);
}

test "udp recv_msg reports pktinfo and timestamp" {
    const host = "127.0.0.1";
    var receiver: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &receiver));
    defer _ = sa_std_close(receiver);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_read_timeout(receiver, 5_000_000_000));
    var local_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_local_addr(receiver, &local_handle));
    defer _ = sa_std_close(local_handle);
    const port = sa_net_addr_port(local_handle);
    try std.testing.expect(port != 0);

    // IPPROTO_IP (0) / IP_PKTINFO (8) and SOL_SOCKET (1) / SO_TIMESTAMP (29),
    // enabled through the new passthrough itself.
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_setsockopt_int(receiver, 0, 8, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_socket_setsockopt_int(receiver, 1, 29, 1));

    var sender: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &sender));
    defer _ = sa_std_close(sender);
    var sender_local: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_local_addr(sender, &sender_local));
    defer _ = sa_std_close(sender_local);
    const sender_port = sa_net_addr_port(sender_local);

    var dest_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_to_socket_addr_first(host.ptr, host.len, port, &dest_handle));
    defer _ = sa_std_close(dest_handle);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_connect_addr(sender, dest_handle));
    const payload = "hello";
    var written: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_send(sender, payload.ptr, payload.len, &written));
    try std.testing.expectEqual(@as(u64, payload.len), written);

    var buf: [64]u8 = undefined;
    var read: u64 = 0;
    var src_addr: u64 = 0;
    var dest_addr: u64 = 0;
    var ifindex: u32 = 0;
    var ts_ns: u64 = 0;
    var flags: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_recv_msg(receiver, &buf, buf.len, &read, &src_addr, &dest_addr, &ifindex, &ts_ns, &flags));
    defer _ = sa_std_close(src_addr);
    defer _ = sa_std_close(dest_addr);
    try std.testing.expectEqual(@as(u64, payload.len), read);
    try std.testing.expectEqualStrings(payload, buf[0..read]);
    try std.testing.expect((flags & recv_msg_flag_pktinfo) != 0);
    try std.testing.expect((flags & recv_msg_flag_timestamp) != 0);
    try std.testing.expect(ifindex != 0);
    try std.testing.expect(ts_ns != 0);
    try std.testing.expectEqual(sender_port, sa_net_addr_port(src_addr));
    try std.testing.expectEqual(@as(u32, 2), sa_net_addr_family(dest_addr));
    try std.testing.expectEqual(port, sa_net_addr_port(dest_addr));
}

test "udp recv_multi drains queued datagrams" {
    const host = "127.0.0.1";
    var receiver: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &receiver));
    defer _ = sa_std_close(receiver);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_read_timeout(receiver, 5_000_000_000));
    var local_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_local_addr(receiver, &local_handle));
    defer _ = sa_std_close(local_handle);
    const port = sa_net_addr_port(local_handle);

    var sender: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &sender));
    defer _ = sa_std_close(sender);
    var sender_local: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_local_addr(sender, &sender_local));
    defer _ = sa_std_close(sender_local);
    const sender_port = sa_net_addr_port(sender_local);
    var dest_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_to_socket_addr_first(host.ptr, host.len, port, &dest_handle));
    defer _ = sa_std_close(dest_handle);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_connect_addr(sender, dest_handle));

    const payloads = [3][]const u8{ "a", "bb", "ccc" };
    for (payloads) |payload| {
        var written: u64 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_send(sender, payload.ptr, payload.len, &written));
        try std.testing.expectEqual(@as(u64, payload.len), written);
    }

    var buf: [128]u8 = undefined;
    var lens: [8]u64 = undefined;
    var addrs: [8]u64 = undefined;
    var count: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_recv_multi(receiver, &buf, buf.len, 16, 8, &count, &lens, &addrs));
    try std.testing.expectEqual(@as(u64, 3), count);
    try std.testing.expectEqual(@as(u64, 1), lens[0]);
    try std.testing.expectEqual(@as(u64, 2), lens[1]);
    try std.testing.expectEqual(@as(u64, 3), lens[2]);
    try std.testing.expectEqual(@as(u8, 'a'), buf[0]);
    try std.testing.expectEqual(@as(u8, 'b'), buf[16]);
    try std.testing.expectEqual(@as(u8, 'b'), buf[17]);
    try std.testing.expectEqual(@as(u8, 'c'), buf[32]);
    try std.testing.expectEqual(@as(u8, 'c'), buf[34]);
    for (addrs[0..3]) |addr_handle| {
        defer _ = sa_std_close(addr_handle);
        try std.testing.expectEqual(sender_port, sa_net_addr_port(addr_handle));
    }

    // Argument discipline: an over-cap batch and a zero slot fail.
    var count2: u64 = 0;
    var lens2: [8]u64 = undefined;
    try std.testing.expect(sa_std_net_udp_recv_multi(receiver, &buf, buf.len, 16, recv_multi_max_msgs + 1, &count2, &lens2, null) != SA_STD_OK);
    try std.testing.expect(sa_std_net_udp_recv_multi(receiver, &buf, buf.len, 0, 8, &count2, &lens2, null) != SA_STD_OK);
}

test "unix datagram peer cred matches own process" {
    var left: u64 = 0;
    var right: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_datagram_pair(&left, &right));
    defer _ = sa_std_close(left);
    defer _ = sa_std_close(right);
    var pid: i32 = 0;
    var uid: u32 = 0;
    var gid: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_datagram_peer_cred(left, &pid, &uid, &gid));
    try std.testing.expectEqual(std.os.linux.getpid(), pid);
    try std.testing.expectEqual(std.os.linux.getuid(), uid);
    try std.testing.expectEqual(std.os.linux.getgid(), gid);

    // An unconnected datagram socket has no peer: the kernel
    // answers SO_PEERCRED with the zero credential (pid 0), which
    // is the documented no-peer sentinel, not an error.
    var lone: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_datagram_unbound(&lone));
    defer _ = sa_std_close(lone);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_datagram_peer_cred(lone, &pid, &uid, &gid));
    try std.testing.expectEqual(@as(i32, 0), pid);
}

test "exported tcp and udp socket setters update live handles" {
    const host = "127.0.0.1";

    var udp_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &udp_handle));
    defer _ = sa_std_close(udp_handle);

    const udp = try ensureSocketHandle(udp_handle);
    try std.testing.expectEqual(@as(@TypeOf(udp.kind), .udp_socket), udp.kind);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_nonblocking(udp_handle, 1));
    const udp_flags = try lxFcntl(udp.fd, std.posix.F.GETFL, 0);
    try std.testing.expect((udp_flags & (@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"))) != 0);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_broadcast(udp_handle, 1));
    try std.testing.expect(try getSocketOptBool(udp.fd, SOLT.SOCKET, SOT.BROADCAST));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_ttl(udp_handle, 64));
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(udp.fd, IPPROTOT.IP, std.posix.IP.TTL));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_read_timeout(udp_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(udp.fd, SOLT.SOCKET, SOT.RCVTIMEO));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_set_write_timeout(udp_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(udp.fd, SOLT.SOCKET, SOT.SNDTIMEO));

    var listener_handle: u64 = 0;
    var bound_port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener_handle, &bound_port));
    defer _ = sa_std_close(listener_handle);
    try std.testing.expect(bound_port != 0);

    var client_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, bound_port, &client_handle));
    defer _ = sa_std_close(client_handle);

    var server_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener_handle, &server_handle));
    defer _ = sa_std_close(server_handle);

    const server = try ensureSocketHandle(server_handle);
    try std.testing.expectEqual(@as(@TypeOf(server.kind), .tcp_stream), server.kind);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_nonblocking(server_handle, 1));
    const server_flags = try lxFcntl(server.fd, std.posix.F.GETFL, 0);
    try std.testing.expect((server_flags & (@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"))) != 0);
    var peek_buf: [1]u8 = undefined;
    // Plain count wrappers report errors negated (W1-DEF-NET-
    // WRITE-AFTER-SHUTDOWN): peek's old +ERR_IO expectation was
    // the conflated contract itself.
    try std.testing.expectEqual(-SA_STD_ERR_IO, sa_net_tcp_stream_peek(server_handle, &peek_buf, peek_buf.len));

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_nodelay(server_handle, 1));
    try std.testing.expect(try getSocketOptBool(server.fd, IPPROTOT.TCP, tcp_nodelay));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_keepalive(server_handle, 1));
    var keepalive_enabled: i32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_keepalive(server_handle, &keepalive_enabled));
    try std.testing.expectEqual(@as(i32, 1), keepalive_enabled);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_ttl(server_handle, 64));
    try std.testing.expectEqual(@as(i32, 64), try getSocketOptInt(server.fd, IPPROTOT.IP, std.posix.IP.TTL));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_read_timeout(server_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(server.fd, SOLT.SOCKET, SOT.RCVTIMEO));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_write_timeout(server_handle, 250_000_000));
    try expectTimeoutRoundedUpWithin(250_000_000, try getSocketOptTimeval(server.fd, SOLT.SOCKET, SOT.SNDTIMEO));
}

test "tcp accept_addr returns peer stream and socket address" {
    const host = "127.0.0.1";
    var listener_handle: u64 = 0;
    var bound_port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener_handle, &bound_port));
    defer _ = sa_std_close(listener_handle);
    try std.testing.expect(bound_port != 0);

    var client_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, bound_port, &client_handle));
    defer _ = sa_std_close(client_handle);

    var server_handle: u64 = 0;
    var peer_addr_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept_addr(listener_handle, &server_handle, &peer_addr_handle));
    defer _ = sa_std_close(server_handle);
    defer _ = sa_net_addr_free(peer_addr_handle);

    try std.testing.expectEqual(@as(u32, 2), sa_net_addr_family(peer_addr_handle));
    try std.testing.expect(sa_net_addr_port(peer_addr_handle) != 0);
    try std.testing.expect(sa_net_addr_host_len(peer_addr_handle) != 0);
}

test "unix socket setters treat tcp-only options as successful no-op" {
    const path = "/tmp/sa_std_unix_setter_test.sock";
    lxUnlink(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    defer lxUnlink(path) catch {};

    var listener_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_listen(path.ptr, path.len, &listener_handle));
    defer _ = sa_std_close(listener_handle);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listener_set_reuseaddr(listener_handle, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listener_set_reuseport(listener_handle, 1));

    var client_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_connect(path.ptr, path.len, &client_handle));
    defer _ = sa_std_close(client_handle);

    var server_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_unix_accept(listener_handle, &server_handle));
    defer _ = sa_std_close(server_handle);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_keepalive(server_handle, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_keepalive_params(server_handle, 60, 10, 5));
}

test "network status maps to stable Rust-style error codes" {
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_from_status(SA_STD_OK));
    try std.testing.expectEqual(@as(i32, 10), sa_std_net_error_code_from_status(SA_STD_ERR_INVALID_ARGUMENT));
    try std.testing.expectEqual(@as(i32, 11), sa_std_net_error_code_from_status(SA_STD_ERR_INVALID_HANDLE));
    try std.testing.expectEqual(@as(i32, 12), sa_std_net_error_code_from_status(SA_STD_ERR_NOT_FOUND));
    try std.testing.expectEqual(@as(i32, 8), sa_std_net_error_code_from_status(SA_STD_ERR_ACCESS));
    try std.testing.expectEqual(@as(i32, 13), sa_std_net_error_code_from_status(SA_STD_ERR_NO_MEMORY));
    try std.testing.expectEqual(@as(i32, 14), sa_std_net_error_code_from_status(SA_STD_ERR_IO));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_status(SA_STD_ERR_NET));
    try std.testing.expectEqual(@as(i32, 9), sa_std_net_error_code_from_status(SA_STD_ERR_UNSUPPORTED));
    try std.testing.expectEqual(@as(i32, 14), sa_std_net_error_code_from_status(SA_STD_ERR_TRUNCATED));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_status(SA_STD_ERR_UNKNOWN));
}

test "hostname reports required length and validates buffers" {
    var length: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_hostname(null, 0, &length));
    try std.testing.expect(length > 0);

    var small: [1]u8 = undefined;
    var small_length: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_hostname(&small, small.len, &small_length));
    try std.testing.expectEqual(length, small_length);
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_hostname(null, 1, &small_length));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_hostname(&small, small.len, null));
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

test "dns forward lookup rejects an unresolvable name" {
    const bad = "nonexistent.invalid";
    var handle: u64 = 77;
    const rc = sa_std_net_to_socket_addr_list(bad.ptr, bad.len, 80, &handle);
    try std.testing.expect(rc != SA_STD_OK);
    try std.testing.expectEqual(@as(u64, 0), handle);
}

test "POSIX errno maps to Rust-style network error kinds" {
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_posix_errno(111));
    try std.testing.expectEqual(@as(i32, 4), sa_std_net_error_code_from_posix_errno(110));
    try std.testing.expectEqual(@as(i32, 6), sa_std_net_error_code_from_posix_errno(11));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_posix_errno(101));
    try std.testing.expectEqual(@as(i32, 21), sa_std_net_error_code_from_posix_errno(113));
    try std.testing.expectEqual(@as(i32, 16), sa_std_net_error_code_from_posix_errno(98));
    try std.testing.expectEqual(@as(i32, 17), sa_std_net_error_code_from_posix_errno(99));
    try std.testing.expectEqual(@as(i32, 18), sa_std_net_error_code_from_posix_errno(104));
    try std.testing.expectEqual(@as(i32, 19), sa_std_net_error_code_from_posix_errno(103));
    try std.testing.expectEqual(@as(i32, 20), sa_std_net_error_code_from_posix_errno(107));
    try std.testing.expectEqual(@as(i32, 22), sa_std_net_error_code_from_posix_errno(32));
    try std.testing.expectEqual(@as(i32, 24), sa_std_net_error_code_from_posix_errno(4));
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_code_from_posix_errno(-2));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_posix_errno(99999));
}

test "WSA error maps to Rust-style network error kinds" {
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_wsa_error(10061));
    try std.testing.expectEqual(@as(i32, 4), sa_std_net_error_code_from_wsa_error(10060));
    try std.testing.expectEqual(@as(i32, 6), sa_std_net_error_code_from_wsa_error(10035));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_wsa_error(10051));
    try std.testing.expectEqual(@as(i32, 21), sa_std_net_error_code_from_wsa_error(10065));
    try std.testing.expectEqual(@as(i32, 16), sa_std_net_error_code_from_wsa_error(10048));
    try std.testing.expectEqual(@as(i32, 17), sa_std_net_error_code_from_wsa_error(10049));
    try std.testing.expectEqual(@as(i32, 18), sa_std_net_error_code_from_wsa_error(10054));
    try std.testing.expectEqual(@as(i32, 19), sa_std_net_error_code_from_wsa_error(10053));
    try std.testing.expectEqual(@as(i32, 20), sa_std_net_error_code_from_wsa_error(10057));
    try std.testing.expectEqual(@as(i32, 24), sa_std_net_error_code_from_wsa_error(10004));
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_code_from_wsa_error(11001));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_wsa_error(99999));
}

test "network error code names are stable" {
    var buffer: [32]u8 = undefined;
    var length: u64 = 0;
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_name(3, &buffer, buffer.len, &length));
    try std.testing.expectEqual(@as(u64, 18), length);
    try std.testing.expectEqualStrings("connection_refused", buffer[0..length]);
    try std.testing.expectEqual(@as(i32, 9), sa_std_net_error_code_name(3, &buffer, 9, &length));
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_name(999, null, 0, &length));
    try std.testing.expectEqualStrings("unknown", netErrorCodeName(999));
}

test "native network error facade reports POSIX platform" {
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_platform());
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_native_error(111));
}

test "TCP connect timeout by resolved address" {
    const host = "127.0.0.1";
    var listener: u64 = 0;
    var port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener, &port));
    defer _ = sa_std_close(listener);

    var address: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_to_socket_addr_first(host.ptr, host.len, port, &address));
    defer _ = sa_net_addr_free(address);

    var client: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect_timeout_addr(address, 500_000_000, &client));
    defer _ = sa_std_close(client);

    var accepted: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener, &accepted));
    defer _ = sa_std_close(accepted);

    var untouched: u64 = 99;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_tcp_connect_timeout_addr(address, 0, &untouched));
    try std.testing.expectEqual(@as(u64, 0), untouched);
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_tcp_connect_timeout_addr(0, 500_000_000, &untouched));
    try std.testing.expectEqual(@as(u64, 0), untouched);
}

test "TCP connect timeout rejects zero duration" {
    var handle: u64 = 99;
    const host = "127.0.0.1";
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_tcp_connect_timeout(host.ptr, host.len, 80, 0, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);
}

test "UDP connect by resolved address" {
    const host = "127.0.0.1";
    var server: u64 = 0;
    var client: u64 = 0;
    var server_addr: u64 = 0;
    var target_addr: u64 = 0;
    var peer_addr: u64 = 0;
    var port: u32 = 0;

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &server));
    defer _ = sa_std_close(server);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_local_addr(server, &server_addr));
    defer _ = sa_net_addr_free(server_addr);
    port = sa_net_addr_port(server_addr);
    try std.testing.expect(port != 0);

    try std.testing.expectEqual(SA_STD_OK, sa_std_net_to_socket_addr_first(host.ptr, host.len, port, &target_addr));
    defer _ = sa_net_addr_free(target_addr);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_bind(host.ptr, host.len, 0, &client));
    defer _ = sa_std_close(client);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_connect_addr(client, target_addr));
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_udp_peer_addr(client, &peer_addr));
    defer _ = sa_net_addr_free(peer_addr);
    try std.testing.expectEqual(port, sa_net_addr_port(peer_addr));
    try std.testing.expectEqual(@as(u32, 2), sa_net_addr_family(peer_addr));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_udp_connect_addr(client, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_udp_connect_addr(0, target_addr));
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

test "tcp stream send_file moves file bytes over loopback" {
    const host = "127.0.0.1";
    const path = "sa_std_sendfile_probe.bin";
    _ = sa_std_fs_remove(path.ptr, path.len);
    var payload_buf: [528]u8 = undefined;
    for (&payload_buf, 0..) |*byte, idx| byte.* = "sendfile-payload-0123456789abcdef"[@mod(idx, 33)];
    const payload: []const u8 = &payload_buf;
    var file_handle: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_write(path.ptr, path.len, 1, &file_handle));
    var written: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_file_write(file_handle, payload.ptr, payload.len, &written));
    try std.testing.expectEqual(@as(u64, payload.len), written);
    try std.testing.expectEqual(SA_STD_OK, sa_std_close(file_handle));
    // sendfile(2) needs a readable input fd: reopen for reading.
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_read(path.ptr, path.len, &file_handle));
    defer {
        _ = sa_std_close(file_handle);
        _ = sa_std_fs_remove(path.ptr, path.len);
    }
    var listener: u64 = 0;
    var bound_port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener, &bound_port));
    defer _ = sa_std_close(listener);
    try std.testing.expect(bound_port != 0);
    var client: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, bound_port, &client));
    defer _ = sa_std_close(client);
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_set_read_timeout(client, 5_000_000_000));
    var server_side: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener, &server_side));
    defer _ = sa_std_close(server_side);

    // Full send from offset 0.
    var sent: u64 = 0;
    var next_offset: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_send_file(server_side, file_handle, 0, payload.len, &sent, &next_offset));
    try std.testing.expectEqual(@as(u64, payload.len), sent);
    try std.testing.expectEqual(@as(u64, payload.len), next_offset);
    var received: [528]u8 = undefined;
    var total: u64 = 0;
    while (total < payload.len) {
        var got: u64 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_read(client, received[total..].ptr, payload.len - total, &got));
        try std.testing.expect(got != 0);
        total += got;
    }
    try std.testing.expectEqualSlices(u8, payload, &received);

    // Offset send: the file position is explicit, so a second send
    // from offset 33 moves exactly payload[33..66].
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_send_file(server_side, file_handle, 33, 33, &sent, &next_offset));
    try std.testing.expectEqual(@as(u64, 33), sent);
    try std.testing.expectEqual(@as(u64, 66), next_offset);
    var slice_buf: [33]u8 = undefined;
    total = 0;
    while (total < 33) {
        var got: u64 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_stream_read(client, slice_buf[total..].ptr, 33 - total, &got));
        try std.testing.expect(got != 0);
        total += got;
    }
    try std.testing.expectEqualSlices(u8, payload[33..66], &slice_buf);

    // Bad handles fail loudly.
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_tcp_stream_send_file(0, file_handle, 0, 1, &sent, &next_offset));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_net_tcp_stream_send_file(server_side, 0, 0, 1, &sent, &next_offset));
}

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
