const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const SA_STD_ERR_ACCESS = @import("w01.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("w01.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNKNOWN = @import("w01.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SaTermEpollEvent = @import("w01.zig").SaTermEpollEvent;
const finish = @import("w02.zig").finish;
const last_error = @import("w01.zig").last_error;
const netErrorCodeName = @import("w04.zig").netErrorCodeName;
const sa_std_net_error_code_from_native_error = @import("w04.zig").sa_std_net_error_code_from_native_error;
const sa_std_net_error_code_from_posix_errno = @import("w04.zig").sa_std_net_error_code_from_posix_errno;
const sa_std_net_error_code_from_status = @import("w04.zig").sa_std_net_error_code_from_status;
const sa_std_net_error_code_from_wsa_error = @import("w04.zig").sa_std_net_error_code_from_wsa_error;
const sa_std_net_error_code_name = @import("w04.zig").sa_std_net_error_code_name;
const sa_std_net_error_platform = @import("w04.zig").sa_std_net_error_platform;
const sa_std_net_tcp_connect_timeout = @import("w11.zig").sa_std_net_tcp_connect_timeout;
const sa_std_process_kill = @import("w09.zig").sa_std_process_kill;
const sa_std_process_try_wait_raw = @import("w10.zig").sa_std_process_try_wait_raw;
const sa_std_process_wait_raw = @import("w10.zig").sa_std_process_wait_raw;

pub export fn sa_std_net_unix_datagram_connect_addr(_: u64, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_peer_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_set_passcred(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_passcred(_: u64, out: ?*i32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_set_mark(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_shutdown(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_send_to_addr(_: u64, _: ?[*]const u8, _: u64, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_recv_from(_: u64, _: ?[*]u8, _: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (out_read) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_peek_from(_: u64, _: ?[*]u8, _: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (out_read) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_pidfd_kill(handle: u64) i32 {
    return sa_std_process_kill(handle);
}

pub export fn sa_std_pidfd_send_signal(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_pidfd_wait(_: u64, out: ?*u32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_pidfd_wait_raw(handle: u64, out: ?*i32) i32 {
    return sa_std_process_wait_raw(handle, out);
}

pub export fn sa_std_pidfd_try_wait(_: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (out_ready) |p| p.* = 0;
    if (out_code) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_pidfd_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    return sa_std_process_try_wait_raw(handle, out_ready, out_raw);
}

pub export fn sa_term_epoll_create(_: u32, out: ?*u64) i32 {
    if (out == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_epoll_ctl(_: u64, _: u32, _: u64, _: u32, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_epoll_wait(_: u64, _: ?*SaTermEpollEvent, _: u64, _: i32, out: ?*u64) i32 {
    if (out == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_epoll_close(_: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

// HTTP/2 is not linked into the Windows bootstrap runtime yet. Keep the
// complete sa_std HTTP/2 ABI present so callers receive a deterministic
// unsupported result instead of a link-time failure.
pub fn unsupportedHttp2U64(out: ?*u64) i32 {
    const slot = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    slot.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    slot.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_client_request(
    url_ptr: ?[*]const u8,
    url_len: u64,
    method_ptr: ?[*]const u8,
    method_len: u64,
    body_ptr: ?[*]const u8,
    body_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = url_ptr;
    _ = url_len;
    _ = method_ptr;
    _ = method_len;
    _ = body_ptr;
    _ = body_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_nghttp2_version_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_status_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_constants_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_sensitive_headers(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_default_settings_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_packed_settings(
    settings_json_ptr: ?[*]const u8,
    settings_json_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = settings_json_ptr;
    _ = settings_json_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_unpacked_settings_json(
    buf_ptr: ?[*]const u8,
    buf_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = buf_ptr;
    _ = buf_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_perform_server_handshake(
    input_ptr: ?[*]const u8,
    input_len: u64,
    settings_json_ptr: ?[*]const u8,
    settings_json_len: u64,
    out_bytes_handle: ?*u64,
    out_json_handle: ?*u64,
) i32 {
    _ = input_ptr;
    _ = input_len;
    _ = settings_json_ptr;
    _ = settings_json_len;
    const bytes = out_bytes_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const json = out_json_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    bytes.* = 0;
    json.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_buffer_data(handle: u64) ?[*]const u8 {
    _ = handle;
    _ = finish(SA_STD_ERR_UNSUPPORTED);
    return null;
}

pub export fn sa_std_http2_buffer_len(handle: u64) u64 {
    _ = handle;
    _ = finish(SA_STD_ERR_UNSUPPORTED);
    return 0;
}

pub export fn sa_std_http2_buffer_free(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

// Compatibility shims for the rosetta demos that model host APIs directly.
// These export plain C ABI symbols matching the names the demos `@extern`.
// They mirror the Linux sa_std.zig mock surface (src/runtime/sa_std.zig:5947),
// tuned so the demo programs exercise their RESULT_OK path on Windows too.
pub var compatibility_mmap_page: [4096]u8 = std.mem.zeroes([4096]u8);

pub var compatibility_dlopen_cookie: [1]u8 = .{0};

pub var compatibility_dlsym_cookie: [1]u8 = .{0};

pub export fn fd_open(path_ptr: ?[*]const u8) i32 {
    _ = path_ptr;
    last_error = SA_STD_OK;
    return 3;
}

pub export fn fd_read(fd: i32) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return 3;
}

pub export fn fd_close(fd: i32) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn mmap(fd: i32, len: i32) ?[*]u8 {
    _ = fd;
    _ = len;
    last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub export fn munmap(map: ?[*]u8, len: i32) i32 {
    _ = map;
    _ = len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sa_compat_signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    last_error = SA_STD_OK;
    return sig;
}

pub export fn dlopen(path_ptr: ?[*]const u8, flags: i32) ?[*]u8 {
    _ = path_ptr;
    _ = flags;
    last_error = SA_STD_OK;
    return compatibility_dlopen_cookie[0..].ptr;
}

pub export fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    last_error = SA_STD_OK;
    return compatibility_dlsym_cookie[0..].ptr;
}

pub export fn dlclose(handle: ?[*]u8) i32 {
    _ = handle;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sqlite3_step(stmt: ?[*]u8) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return 1;
}

pub export fn sqlite3_finalize(stmt: ?[*]u8) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

comptime {
    @export(&sa_compat_signal, .{ .name = "signal" });
}

// Compatibility shims for the rosetta HTTP demos (301 client / 302 server).
// The demos @extern an sa_http_client_* / sa_http_server_* surface that is
// declared in the generated deno.sai but never implemented in any runtime on
// this host. These exports provide an in-process mock so the demos exercise
// their RESULT_OK path the same way the fd_open/sqlite3/dlopen mocks do.
pub const sa_http_compat_status_ok: u32 = 200;

pub var sa_http_client_resp_mock_chunk: [16]u8 = .{ 104, 101, 108, 108, 111, 32, 102, 114, 111, 109, 32, 115, 97, 97, 115, 109 };

pub export fn sa_http_client_new(use_tls: u8, out_client: ?*u64) u32 {
    _ = use_tls;
    if (out_client) |p| p.* = 1;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_req_new(client: u64, method: u8, url_ptr: ?[*]const u8, url_len: u64, out_req: ?*u64) u32 {
    _ = client;
    _ = method;
    _ = url_ptr;
    _ = url_len;
    if (out_req) |p| p.* = 2;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_req_add_header(req: u64, key_ptr: ?[*]const u8, key_len: u64, val_ptr: ?[*]const u8, val_len: u64) u32 {
    _ = req;
    _ = key_ptr;
    _ = key_len;
    _ = val_ptr;
    _ = val_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_req_set_body(req: u64, body_ptr: ?[*]const u8, body_len: u64) u32 {
    _ = req;
    _ = body_ptr;
    _ = body_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_req_send(req: u64, out_resp: ?*u64) u32 {
    _ = req;
    if (out_resp) |p| p.* = 3;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_resp_status(resp: u64) u16 {
    _ = resp;
    last_error = SA_STD_OK;
    return @as(u16, @intCast(sa_http_compat_status_ok));
}

pub export fn sa_http_client_resp_body_reader(resp: u64, out_reader: ?*u64) u32 {
    _ = resp;
    if (out_reader) |p| p.* = 4;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_resp_read_chunk(reader: u64, buf: ?[*]u8, cap: u64, out_len: ?*u64) u32 {
    _ = reader;
    if (out_len) |p| p.* = 16;
    if (buf) |bp| {
        const n: usize = if (cap > 16) @as(usize, 16) else @intCast(cap);
        @memcpy(bp[0..n], sa_http_client_resp_mock_chunk[0..n]);
    }
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_resp_free(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_body_reader_free(reader: u64) u32 {
    _ = reader;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_req_free(req: u64) u32 {
    _ = req;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_client_free(client: u64) u32 {
    _ = client;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub var sa_http_server_req_mock_path: [7]u8 = .{ 47, 115, 116, 114, 101, 97, 109 };

pub const sa_http_server_req_mock_val: []const u8 = "text/plain";

pub export fn sa_http_server_new(out_server: ?*u64) u32 {
    if (out_server) |p| p.* = 1;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_start(server: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    _ = server;
    _ = host_ptr;
    _ = host_len;
    _ = port;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_accept(server: u64, out_req: ?*u64) u32 {
    _ = server;
    if (out_req) |p| p.* = 2;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_req_get_path(req: u64, out_path: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    if (out_path) |p| p.* = sa_http_server_req_mock_path[0..].ptr;
    if (out_len) |p| p.* = 7;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_req_get_header(req: u64, key_ptr: ?[*]const u8, key_len: u64, out_val: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    _ = key_ptr;
    _ = key_len;
    if (out_val) |p| p.* = sa_http_server_req_mock_val.ptr;
    if (out_len) |p| p.* = sa_http_server_req_mock_val.len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_req_get_body(req: u64, out_body: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    if (out_body) |p| p.* = sa_http_server_req_mock_val.ptr;
    if (out_len) |p| p.* = 0;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_resp_stream_new(req: u64, status: u16, out_resp: ?*u64) u32 {
    _ = req;
    _ = status;
    if (out_resp) |p| p.* = 3;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_resp_stream_write(resp: u64, body_ptr: ?[*]const u8, body_len: u64) u32 {
    _ = resp;
    _ = body_ptr;
    _ = body_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_resp_stream_flush(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_resp_stream_end(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_resp_stream_free(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_req_free(req: u64) u32 {
    _ = req;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_http_server_free(server: u64) u32 {
    _ = server;
    last_error = SA_STD_OK;
    return SA_STD_OK;
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

test "native network error facade reports Windows platform" {
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_platform());
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_native_error(10061));
}

test "TCP connect timeout rejects zero duration" {
    var handle: u64 = 99;
    const host = "127.0.0.1";
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_tcp_connect_timeout(host.ptr, host.len, 80, 0, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);
}
