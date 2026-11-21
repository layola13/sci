const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const H3DataReader = @import("q01.zig").H3DataReader;
const H3Nv = @import("q01.zig").H3Nv;
const H3_NV_FLAG_NONE = @import("q01.zig").H3_NV_FLAG_NONE;
const SA_STD_ERR_AGAIN = @import("q01.zig").SA_STD_ERR_AGAIN;
const SA_STD_ERR_INVALID_ARGUMENT = @import("q01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("q01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("q01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("q01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("q01.zig").SA_STD_OK;
const SockStorage = @import("q01.zig").SockStorage;
const h3ReadData = @import("q03.zig").h3ReadData;
const loadGnuApi = @import("q01.zig").loadGnuApi;
const loadH3Api = @import("q01.zig").loadH3Api;
const loadNgApi = @import("q01.zig").loadNgApi;
const lxBind = @import("q02.zig").lxBind;
const lxClose = @import("q02.zig").lxClose;
const parseIp4Literal = @import("q02.zig").parseIp4Literal;
const quicStackAvailable = @import("q01.zig").quicStackAvailable;
const sa_std_http3_session_bind = @import("q03.zig").sa_std_http3_session_bind;
const sa_std_http3_session_create = @import("q03.zig").sa_std_http3_session_create;
const sa_std_http3_session_destroy = @import("q03.zig").sa_std_http3_session_destroy;
const sa_std_quic_client_connect = @import("q02.zig").sa_std_quic_client_connect;
const sa_std_quic_conn_close = @import("q02.zig").sa_std_quic_conn_close;
const sa_std_quic_conn_handshake_completed = @import("q02.zig").sa_std_quic_conn_handshake_completed;
const sa_std_quic_conn_poll = @import("q03.zig").sa_std_quic_conn_poll;
const sa_std_quic_endpoint_create = @import("q02.zig").sa_std_quic_endpoint_create;
const sa_std_quic_endpoint_destroy = @import("q02.zig").sa_std_quic_endpoint_destroy;
const sa_std_quic_server_accept = @import("q03.zig").sa_std_quic_server_accept;
const sa_std_quic_server_listen = @import("q02.zig").sa_std_quic_server_listen;
const sa_std_quic_server_poll = @import("q03.zig").sa_std_quic_server_poll;
const sa_std_quic_stream_open = @import("q03.zig").sa_std_quic_stream_open;
const sa_std_quic_stream_read = @import("q03.zig").sa_std_quic_stream_read;
const sa_std_quic_stream_write = @import("q03.zig").sa_std_quic_stream_write;
const sessionFrom = @import("q03.zig").sessionFrom;
const socketLocalAddr = @import("q02.zig").socketLocalAddr;
const storageFromIn = @import("q02.zig").storageFromIn;
const strArg = @import("q02.zig").strArg;
const u64ToUsize = @import("q01.zig").u64ToUsize;
const udpSocket = @import("q02.zig").udpSocket;

pub export fn sa_std_http3_submit_request(session: u64, method_ptr: ?[*]const u8, method_len: u64, authority_ptr: ?[*]const u8, authority_len: u64, path_ptr: ?[*]const u8, path_len: u64, body_ptr: ?[*]const u8, body_len: u64, out_stream_id: ?*i64) i32 {
    const slot = out_stream_id orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = -1;
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (sess.is_server) return SA_STD_ERR_INVALID_ARGUMENT;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ha = loadH3Api() orelse return SA_STD_ERR_UNSUPPORTED;
    const qc = sess.qc orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const method = strArg(method_ptr, method_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const authority = strArg(authority_ptr, authority_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const path = strArg(path_ptr, path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const body = strArg(body_ptr, body_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (method.len == 0 or authority.len == 0 or path.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (!sess.bound) sess.maybeBind();
    var sid: i64 = -1;
    if (ng.conn_open_bidi_stream(qc.conn, &sid, null) != 0) return SA_STD_ERR_IO;
    const st = sess.ensureStream(sid) catch return SA_STD_ERR_NO_MEMORY;
    st.send_body = std.heap.page_allocator.dupe(u8, body) catch return SA_STD_ERR_NO_MEMORY;
    var len_buf: [16]u8 = undefined;
    const len_s = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable;
    const nvs = [_]H3Nv{
        .{ .name = ":method".ptr, .value = method.ptr, .namelen = 7, .valuelen = method.len, .flags = H3_NV_FLAG_NONE },
        .{ .name = ":scheme".ptr, .value = "https".ptr, .namelen = 7, .valuelen = 5, .flags = H3_NV_FLAG_NONE },
        .{ .name = ":authority".ptr, .value = authority.ptr, .namelen = 10, .valuelen = authority.len, .flags = H3_NV_FLAG_NONE },
        .{ .name = ":path".ptr, .value = path.ptr, .namelen = 5, .valuelen = path.len, .flags = H3_NV_FLAG_NONE },
        .{ .name = "content-length".ptr, .value = len_s.ptr, .namelen = 14, .valuelen = len_s.len, .flags = H3_NV_FLAG_NONE },
    };
    const reader = H3DataReader{ .read_data = &h3ReadData };
    const dr: ?*const H3DataReader = if (body.len > 0) &reader else null;
    if (ha.submit_request(sess.h3, sid, &nvs, nvs.len, dr, null) != 0) return SA_STD_ERR_IO;
    slot.* = sid;
    return SA_STD_OK;
}

pub export fn sa_std_http3_server_next_request(session: u64, out_stream_id: ?*i64) i32 {
    const slot = out_stream_id orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = -1;
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (!sess.is_server) return SA_STD_ERR_INVALID_ARGUMENT;
    if (sess.pending_requests.items.len == 0) return SA_STD_ERR_AGAIN;
    slot.* = sess.pending_requests.orderedRemove(0);
    return SA_STD_OK;
}

pub export fn sa_std_http3_request_field(session: u64, stream_id: i64, name_ptr: ?[*]const u8, name_len: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const name = strArg(name_ptr, name_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const st = sess.getStream(stream_id) orelse return SA_STD_ERR_AGAIN;
    const v = st.header(name) orelse return SA_STD_ERR_AGAIN;
    return writeStringOut(out, out_cap, out_len, v);
}

pub export fn sa_std_http3_submit_response(session: u64, stream_id: i64, status: u32, body_ptr: ?[*]const u8, body_len: u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (!sess.is_server) return SA_STD_ERR_INVALID_ARGUMENT;
    const ha = loadH3Api() orelse return SA_STD_ERR_UNSUPPORTED;
    const body = strArg(body_ptr, body_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const st = sess.ensureStream(stream_id) catch return SA_STD_ERR_NO_MEMORY;
    if (st.send_body.len > 0) std.heap.page_allocator.free(st.send_body);
    st.send_body = std.heap.page_allocator.dupe(u8, body) catch return SA_STD_ERR_NO_MEMORY;
    st.send_off = 0;
    var status_buf: [8]u8 = undefined;
    const status_s = std.fmt.bufPrint(&status_buf, "{d}", .{status}) catch unreachable;
    var len_buf: [16]u8 = undefined;
    const len_s = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable;
    const nvs = [_]H3Nv{
        .{ .name = ":status".ptr, .value = status_s.ptr, .namelen = 7, .valuelen = status_s.len, .flags = H3_NV_FLAG_NONE },
        .{ .name = "content-length".ptr, .value = len_s.ptr, .namelen = 14, .valuelen = len_s.len, .flags = H3_NV_FLAG_NONE },
    };
    const reader = H3DataReader{ .read_data = &h3ReadData };
    const dr: ?*const H3DataReader = &reader;
    if (ha.submit_response(sess.h3, stream_id, &nvs, nvs.len, dr) != 0) return SA_STD_ERR_IO;
    return SA_STD_OK;
}

pub export fn sa_std_http3_response_status(session: u64, stream_id: i64, out: ?*u32) i32 {
    const slot = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const st = sess.getStream(stream_id) orelse return SA_STD_ERR_AGAIN;
    if (st.status == 0) return SA_STD_ERR_AGAIN;
    slot.* = st.status;
    return SA_STD_OK;
}

pub export fn sa_std_http3_stream_read(session: u64, stream_id: i64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_fin: ?*u32) i32 {
    const rslot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    rslot.* = 0;
    if (out_fin) |f| f.* = 0;
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const st = sess.getStream(stream_id) orelse return SA_STD_ERR_AGAIN;
    const avail = st.body.items.len - st.body_off;
    const n = @min(avail, u64ToUsize(cap) orelse return SA_STD_ERR_INVALID_ARGUMENT);
    if (n > 0) {
        const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
        @memcpy(buf[0..n], st.body.items[st.body_off..][0..n]);
        st.body_off += n;
        rslot.* = @intCast(n);
    }
    if (out_fin) |f| f.* = if (st.body_fin and st.body_off >= st.body.items.len) 1 else 0;
    if (n == 0 and !st.body_fin) return SA_STD_ERR_AGAIN;
    return SA_STD_OK;
}

pub const SA_STD_ERR_TRUNCATED: i32 = 9;

pub fn writeStringOut(out: ?[*]u8, out_cap: u64, out_len: ?*u64, bytes: []const u8) i32 {
    const len_ptr = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    len_ptr.* = @intCast(bytes.len);
    if (out_cap == 0) return SA_STD_OK;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const cap = u64ToUsize(out_cap) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = @min(cap, bytes.len);
    @memcpy(buf[0..n], bytes[0..n]);
    if (n != bytes.len) return SA_STD_ERR_TRUNCATED;
    return SA_STD_OK;
}

// ---- capability surface (kept from the skeleton; probes now reflect the
// ---- real dlopen stack: ngtcp2 + its GnuTLS crypto backend + nghttp3) ---------
pub export fn sa_std_quic_supported(out: ?*u32) i32 {
    const slot = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (quicStackAvailable()) 1 else 0;
    return SA_STD_OK;
}

pub export fn sa_std_http3_supported(out: ?*u32) i32 {
    const slot = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (quicStackAvailable()) 1 else 0;
    return SA_STD_OK;
}

// String output handle convention (local registry, same shape as the http2
// and tls modules). data/len/free live below.
pub var string_mutex = std.Io.Mutex.init;

pub var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

pub fn registerString(bytes: []u8, slot: *u64) i32 {
    string_mutex.lockUncancelable(sio.io());
    defer string_mutex.unlock(sio.io());
    var i: usize = 0;
    while (i < string_registry.items.len) : (i += 1) {
        if (string_registry.items[i] == null) {
            string_registry.items[i] = bytes;
            slot.* = @intCast(i + 1);
            return SA_STD_OK;
        }
    }
    string_registry.append(std.heap.page_allocator, bytes) catch return SA_STD_ERR_NO_MEMORY;
    slot.* = @intCast(string_registry.items.len);
    return SA_STD_OK;
}

pub fn takeString(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    string_mutex.lockUncancelable(sio.io());
    defer string_mutex.unlock(sio.io());
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return null;
    return string_registry.items[idx];
}

pub export fn sa_std_quic_buffer_data(handle: u64) ?[*]const u8 {
    return if (takeString(handle)) |s| s.ptr else null;
}

pub export fn sa_std_quic_buffer_len(handle: u64) u64 {
    return if (takeString(handle)) |s| @intCast(s.len) else 0;
}

pub export fn sa_std_quic_buffer_free(handle: u64) i32 {
    string_mutex.lockUncancelable(sio.io());
    defer string_mutex.unlock(sio.io());
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

pub fn registerOwned(text: []const u8, slot: *u64) i32 {
    const owned = std.heap.page_allocator.dupe(u8, text) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

pub export fn sa_std_quic_capabilities_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [512]u8 = undefined;
    const ngtcp2 = loadNgApi() != null;
    const nghttp3 = loadH3Api() != null;
    const gnutls = loadGnuApi() != null;
    const supported = ngtcp2 and nghttp3 and gnutls;
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"quic\",\"supported\":{s},\"ngtcp2\":{s},\"nghttp3\":{s},\"gnutls\":{s},\"openssl\":false,\"alpn\":[\"h3\"],\"protocolMachine\":{s},\"reason\":\"{s}\"}}", .{
        if (supported) "true" else "false",
        if (ngtcp2) "true" else "false",
        if (nghttp3) "true" else "false",
        if (gnutls) "true" else "false",
        if (supported) "true" else "false",
        if (supported) "ngtcp2 + GnuTLS crypto backend + nghttp3 are available" else "libngtcp2, libngtcp2_crypto_gnutls, libgnutls and libnghttp3 are required for QUIC sessions",
    }) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

pub export fn sa_std_quic_constants_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return registerOwned(
        \\{"cc":{"RENO":"reno","CUBIC":"cubic","BBR":"bbr"},"DEFAULT_CIPHERS":"TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_CCM_SHA256","DEFAULT_GROUPS":"X25519:P-256:P-384:P-521","ALPN_H3":"h3","STREAM_DIRECTION_BIDIRECTIONAL":0,"STREAM_DIRECTION_UNIDIRECTIONAL":1}
    , slot);
}

pub export fn sa_std_http3_constants_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return registerOwned(
        \\{"ALPN_H3":"h3","RFC_HTTP3":9114,"RFC_QPACK":9204,"RFC_HTTP_DATAGRAM":9297,"RFC_WEBSOCKETS_OVER_HTTP3":9220}
    , slot);
}

// ============================================================================
// Unit tests.
// ============================================================================
pub const testing = std.testing;

pub fn stackAvailable() bool {
    var flag: u32 = 0;
    if (sa_std_quic_supported(&flag) != SA_STD_OK) return false;
    return flag == 1;
}

// On hosts where the stack MUST be present (the dev/CI box), set
// SCI_REQUIRE_QUIC=1 so a missing library fails loudly instead of
// silently skipping the loopback tests.
pub fn stackOrSkip() !bool {
    if (stackAvailable()) return true;
    if (std.c.getenv("SCI_REQUIRE_QUIC") != null) return error.StackMissing;
    return false;
}

test "supported reports the real host stack" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_supported(&flag));
    try testing.expect(flag == 0 or flag == 1);
    var hflag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_supported(&hflag));
    try testing.expectEqual(flag, hflag);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_quic_supported(null));
}

test "capabilities json tracks the real stack and is not faked" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_capabilities_json(&handle));
    defer _ = sa_std_quic_buffer_free(handle);
    const ptr = sa_std_quic_buffer_data(handle) orelse return error.MissingData;
    const json = ptr[0..@intCast(sa_std_quic_buffer_len(handle))];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"quic\"") != null);
    const ngtcp2 = std.mem.indexOf(u8, json, "\"ngtcp2\":true") != null;
    const nghttp3 = std.mem.indexOf(u8, json, "\"nghttp3\":true") != null;
    const gnutls = std.mem.indexOf(u8, json, "\"gnutls\":true") != null;
    var flag: u32 = 0;
    _ = sa_std_quic_supported(&flag);
    try testing.expectEqual(ngtcp2 and nghttp3 and gnutls, flag == 1);
    const pm_idx = std.mem.indexOf(u8, json, "\"protocolMachine\":") orelse return error.MissingPM;
    try testing.expect(std.mem.startsWith(u8, json[pm_idx + "\"protocolMachine\":".len..], if (flag == 1) "true" else "false"));
}

test "constants json is present for both quic and http3" {
    var q: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_constants_json(&q));
    defer _ = sa_std_quic_buffer_free(q);
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_constants_json(&h));
    defer _ = sa_std_quic_buffer_free(h);
    const qd = sa_std_quic_buffer_data(q) orelse return error.Missing;
    try testing.expect(std.mem.indexOf(u8, qd[0..@intCast(sa_std_quic_buffer_len(q))], "ALPN_H3") != null);
    const hd = sa_std_quic_buffer_data(h) orelse return error.Missing;
    try testing.expect(std.mem.indexOf(u8, hd[0..@intCast(sa_std_quic_buffer_len(h))], "RFC_HTTP3") != null);
}

test "buffer handle double-free and invalid-handle invariants" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_capabilities_json(&handle));
    try testing.expect(handle != 0);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_quic_buffer_free(handle));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_quic_buffer_data(handle));
    try testing.expectEqual(@as(u64, 0), sa_std_quic_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_buffer_free(0));
}

test "endpoint and session constructors validate arguments" {
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_quic_endpoint_create(null));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http3_session_create(null));
    if (!stackAvailable()) return;
    var ep: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_endpoint_create(&ep));
    try testing.expect(ep != 0);
    defer _ = sa_std_quic_endpoint_destroy(ep);
    var sess: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_session_create(&sess));
    try testing.expect(sess != 0);
    defer _ = sa_std_http3_session_destroy(sess);
    // bind rejects a bogus conn handle value type-wise (0)
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http3_session_bind(sess, 0));
    // client connect argument validation happens before any socket work
    var conn: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_quic_client_connect(0, "localhost".ptr, 9, 0, null, 0, null, 0, null, 0, &conn));
}

// ---- loopback helpers ----
pub fn makeCertPair(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, "cert.pem" });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, "key.pem" });
    errdefer allocator.free(key_path);
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "1", "-nodes", "-subj", "/CN=localhost",
        "-addext", "subjectAltName=DNS:localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    switch (term) {
        .exited => |code| if (code != 0) return error.CertFailed,
        else => return error.CertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
}

pub fn freeUdpPort() !u16 {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return freeUdpPortNative();
    }
}

pub fn freeUdpPortNative() !u16 {
    const fd = try udpSocket();
    defer lxClose(fd);
    const addr = parseIp4Literal("127.0.0.1", 0).?;
    const bs = storageFromIn(addr);
    if (lxBind(fd, &bs.storage, bs.len) < 0) return error.BindFailed;
    var storage: SockStorage = undefined;
    var len: std.posix.socklen_t = @sizeOf(SockStorage);
    try socketLocalAddr(fd, &storage, &len);
    const sa: *const std.posix.sockaddr.in = @ptrCast(@alignCast(&storage));
    return std.mem.bigToNative(u16, sa.port);
}

pub const Loopback = struct {
    ep: u64 = 0,
    client: u64 = 0,
    server: u64 = 0,
    port: u16,

    fn pump(self: *Loopback, rounds: usize) void {
        for (0..rounds) |_| {
            _ = sa_std_quic_server_poll(self.ep, 2);
            if (self.client != 0) _ = sa_std_quic_conn_poll(self.client, 2);
            if (self.server != 0) _ = sa_std_quic_conn_poll(self.server, 0);
            if (self.server == 0) {
                var sc: u64 = 0;
                if (sa_std_quic_server_accept(self.ep, &sc) == SA_STD_OK) self.server = sc;
            }
        }
    }
    fn handshakeDone(self: *Loopback) bool {
        var a: u32 = 0;
        var b: u32 = 0;
        if (self.client == 0 or self.server == 0) return false;
        _ = sa_std_quic_conn_handshake_completed(self.client, &a);
        _ = sa_std_quic_conn_handshake_completed(self.server, &b);
        return a == 1 and b == 1;
    }
    fn deinit(self: *Loopback) void {
        if (self.client != 0) _ = sa_std_quic_conn_close(self.client);
        if (self.server != 0) _ = sa_std_quic_conn_close(self.server);
        if (self.ep != 0) _ = sa_std_quic_endpoint_destroy(self.ep);
    }
};

pub fn setupLoopback(allocator: std.mem.Allocator, td: *testing.TmpDir) !Loopback {
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeCertPair(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);
    const port = try freeUdpPort();
    var lb = Loopback{ .port = port };
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_endpoint_create(&lb.ep));
    errdefer lb.deinit();
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_server_listen(lb.ep, port, paths.cert.ptr, paths.cert.len, paths.key.ptr, paths.key.len));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_client_connect(0, "localhost".ptr, 9, port, "localhost".ptr, 9, paths.cert.ptr, paths.cert.len, null, 0, &lb.client));
    var i: usize = 0;
    while (i < 300 and !lb.handshakeDone()) : (i += 1) lb.pump(1);
    try testing.expect(lb.handshakeDone());
    return lb;
}

test "loopback: QUIC handshake completes and raw streams echo" {
    if (!try stackOrSkip()) return;
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    var lb = try setupLoopback(allocator, &td);
    defer lb.deinit();

    var sid: i64 = -1;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_stream_open(lb.client, &sid));
    try testing.expect(sid >= 0);
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_stream_write(lb.client, sid, "ping-quic".ptr, 9, 1, &written));
    try testing.expectEqual(@as(u64, 9), written);

    var got: [64]u8 = undefined;
    var got_len: u64 = 0;
    var got_fin: u32 = 0;
    var rounds: usize = 0;
    while (rounds < 300) : (rounds += 1) {
        lb.pump(1);
        const rc = sa_std_quic_stream_read(lb.server, sid, &got, got.len, &got_len, &got_fin);
        if (rc == SA_STD_OK and got_len > 0) break;
    }
    try testing.expectEqualStrings("ping-quic", got[0..@intCast(got_len)]);
    try testing.expectEqual(@as(u32, 1), got_fin);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_quic_stream_write(lb.server, sid, "pong-quic".ptr, 9, 1, &written));
    got_len = 0;
    got_fin = 0;
    rounds = 0;
    while (rounds < 300) : (rounds += 1) {
        lb.pump(1);
        const rc = sa_std_quic_stream_read(lb.client, sid, &got, got.len, &got_len, &got_fin);
        if (rc == SA_STD_OK and got_len > 0) break;
    }
    try testing.expectEqualStrings("pong-quic", got[0..@intCast(got_len)]);
    try testing.expectEqual(@as(u32, 1), got_fin);
}

test "loopback: HTTP/3 GET round trip" {
    if (!try stackOrSkip()) return;
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    var lb = try setupLoopback(allocator, &td);
    defer lb.deinit();

    var client_sess: u64 = 0;
    var server_sess: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_session_create(&client_sess));
    defer _ = sa_std_http3_session_destroy(client_sess);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_session_create(&server_sess));
    defer _ = sa_std_http3_session_destroy(server_sess);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_session_bind(client_sess, lb.client));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_session_bind(server_sess, lb.server));
    lb.pump(20);

    var auth_buf: [64]u8 = undefined;
    const auth = std.fmt.bufPrint(&auth_buf, "localhost:{d}", .{lb.port}) catch unreachable;
    var sid: i64 = -1;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_submit_request(client_sess, "GET".ptr, 3, auth.ptr, auth.len, "/hello".ptr, 6, null, 0, &sid));
    try testing.expect(sid >= 0);

    var req_sid: i64 = -1;
    var rounds: usize = 0;
    while (rounds < 300) : (rounds += 1) {
        lb.pump(1);
        if (sa_std_http3_server_next_request(server_sess, &req_sid) == SA_STD_OK) break;
    }
    try testing.expectEqual(sid, req_sid);
    var field_buf: [64]u8 = undefined;
    var field_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_request_field(server_sess, req_sid, ":path".ptr, 5, &field_buf, field_buf.len, &field_len));
    try testing.expectEqualStrings("/hello", field_buf[0..@intCast(field_len)]);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_request_field(server_sess, req_sid, ":method".ptr, 7, &field_buf, field_buf.len, &field_len));
    try testing.expectEqualStrings("GET", field_buf[0..@intCast(field_len)]);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http3_submit_response(server_sess, req_sid, 200, "hello-h3".ptr, 8));

    var status: u32 = 0;
    rounds = 0;
    while (rounds < 300) : (rounds += 1) {
        lb.pump(1);
        if (sa_std_http3_response_status(client_sess, sid, &status) == SA_STD_OK) break;
    }
    try testing.expectEqual(@as(u32, 200), status);

    var body: [64]u8 = undefined;
    var body_len: u64 = 0;
    var body_fin: u32 = 0;
    rounds = 0;
    while (rounds < 300) : (rounds += 1) {
        lb.pump(1);
        const rc = sa_std_http3_stream_read(client_sess, sid, &body, body.len, &body_len, &body_fin);
        if (rc == SA_STD_OK and body_fin == 1) break;
    }
    try testing.expectEqualStrings("hello-h3", body[0..@intCast(body_len)]);
    try testing.expectEqual(@as(u32, 1), body_fin);
}
