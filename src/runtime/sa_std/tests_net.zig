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
const sa_std_net_tcp_connect_timeout = @import("../sa_std.zig").sa_std_net_tcp_connect_timeout;
const sa_std_net_tcp_connect_timeout_addr = @import("../sa_std.zig").sa_std_net_tcp_connect_timeout_addr;
const sa_std_net_udp_peer_addr = @import("../sa_std.zig").sa_std_net_udp_peer_addr;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_fs_file_write = @import("../sa_std.zig").sa_std_fs_file_write;
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
const sa_std_net_poll_wait = @import("../sa_std.zig").sa_std_net_poll_wait;
const sa_std_net_raw_socket = @import("../sa_std.zig").sa_std_net_raw_socket;
const sa_std_net_socket_getsockopt = @import("../sa_std.zig").sa_std_net_socket_getsockopt;
const sa_std_net_socket_getsockopt_int = @import("../sa_std.zig").sa_std_net_socket_getsockopt_int;
const sa_std_net_socket_setsockopt = @import("../sa_std.zig").sa_std_net_socket_setsockopt;
const sa_std_net_socket_setsockopt_int = @import("../sa_std.zig").sa_std_net_socket_setsockopt_int;
const sa_std_net_tcp_accept = @import("../sa_std.zig").sa_std_net_tcp_accept;
const sa_std_net_tcp_accept_addr = @import("../sa_std.zig").sa_std_net_tcp_accept_addr;
const sa_std_net_tcp_connect = @import("../sa_std.zig").sa_std_net_tcp_connect;
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
const setSocketOptBool = @import("../sa_std.zig").setSocketOptBool;
const setSocketOptInt = @import("../sa_std.zig").setSocketOptInt;
const setSocketOptTimeval = @import("../sa_std.zig").setSocketOptTimeval;
const tcp_nodelay = @import("../sa_std.zig").tcp_nodelay;
const timevalFromNs = @import("../sa_std.zig").timevalFromNs;

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
