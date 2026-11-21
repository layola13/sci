const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const CB_ACKED_STREAM_DATA_OFFSET = @import("q01.zig").CB_ACKED_STREAM_DATA_OFFSET;
const CB_CLIENT_INITIAL = @import("q01.zig").CB_CLIENT_INITIAL;
const CB_DECRYPT = @import("q01.zig").CB_DECRYPT;
const CB_DELETE_CRYPTO_AEAD_CTX = @import("q01.zig").CB_DELETE_CRYPTO_AEAD_CTX;
const CB_DELETE_CRYPTO_CIPHER_CTX = @import("q01.zig").CB_DELETE_CRYPTO_CIPHER_CTX;
const CB_ENCRYPT = @import("q01.zig").CB_ENCRYPT;
const CB_GET_NEW_CONNECTION_ID = @import("q01.zig").CB_GET_NEW_CONNECTION_ID;
const CB_GET_PATH_CHALLENGE_DATA = @import("q01.zig").CB_GET_PATH_CHALLENGE_DATA;
const CB_HANDSHAKE_COMPLETED = @import("q01.zig").CB_HANDSHAKE_COMPLETED;
const CB_HP_MASK = @import("q01.zig").CB_HP_MASK;
const CB_RAND = @import("q01.zig").CB_RAND;
const CB_RECV_CLIENT_INITIAL = @import("q01.zig").CB_RECV_CLIENT_INITIAL;
const CB_RECV_CRYPTO_DATA = @import("q01.zig").CB_RECV_CRYPTO_DATA;
const CB_RECV_RETRY = @import("q01.zig").CB_RECV_RETRY;
const CB_RECV_STREAM_DATA = @import("q01.zig").CB_RECV_STREAM_DATA;
const CB_STREAM_CLOSE = @import("q01.zig").CB_STREAM_CLOSE;
const CB_UPDATE_KEY = @import("q01.zig").CB_UPDATE_KEY;
const CB_VERSION_NEGOTIATION = @import("q01.zig").CB_VERSION_NEGOTIATION;
const GNUTLS_ALPN_MANDATORY = @import("q01.zig").GNUTLS_ALPN_MANDATORY;
const GNUTLS_CLIENT = @import("q01.zig").GNUTLS_CLIENT;
const GNUTLS_CRD_CERTIFICATE = @import("q01.zig").GNUTLS_CRD_CERTIFICATE;
const GNUTLS_NAME_DNS = @import("q01.zig").GNUTLS_NAME_DNS;
const GNUTLS_SERVER = @import("q01.zig").GNUTLS_SERVER;
const GNUTLS_X509_FMT_PEM = @import("q01.zig").GNUTLS_X509_FMT_PEM;
const GTLS_PRIORITY = @import("q01.zig").GTLS_PRIORITY;
const GnuApi = @import("q01.zig").GnuApi;
const GnuCred = @import("q01.zig").GnuCred;
const GnuDatum = @import("q01.zig").GnuDatum;
const GnuSession = @import("q01.zig").GnuSession;
const NG_ERR_WRITE_MORE = @import("q01.zig").NG_ERR_WRITE_MORE;
const NG_PROTO_VER_V1 = @import("q01.zig").NG_PROTO_VER_V1;
const NG_SETTINGS_OFF_INITIAL_TS = @import("q01.zig").NG_SETTINGS_OFF_INITIAL_TS;
const NG_SETTINGS_SIZE = @import("q01.zig").NG_SETTINGS_SIZE;
const NG_STREAM_DATA_FLAG_FIN = @import("q01.zig").NG_STREAM_DATA_FLAG_FIN;
const NG_TP_OFF_ACTIVE_CID_LIMIT = @import("q01.zig").NG_TP_OFF_ACTIVE_CID_LIMIT;
const NG_TP_OFF_MAX_DATA = @import("q01.zig").NG_TP_OFF_MAX_DATA;
const NG_TP_OFF_MAX_IDLE_TIMEOUT = @import("q01.zig").NG_TP_OFF_MAX_IDLE_TIMEOUT;
const NG_TP_OFF_MAX_STREAMS_BIDI = @import("q01.zig").NG_TP_OFF_MAX_STREAMS_BIDI;
const NG_TP_OFF_MAX_STREAMS_UNI = @import("q01.zig").NG_TP_OFF_MAX_STREAMS_UNI;
const NG_TP_OFF_MAX_STREAM_DATA_BIDI_LOCAL = @import("q01.zig").NG_TP_OFF_MAX_STREAM_DATA_BIDI_LOCAL;
const NG_TP_OFF_MAX_STREAM_DATA_BIDI_REMOTE = @import("q01.zig").NG_TP_OFF_MAX_STREAM_DATA_BIDI_REMOTE;
const NG_TP_OFF_MAX_STREAM_DATA_UNI = @import("q01.zig").NG_TP_OFF_MAX_STREAM_DATA_UNI;
const NG_TP_OFF_ORIGINAL_DCID = @import("q01.zig").NG_TP_OFF_ORIGINAL_DCID;
const NG_TP_SIZE = @import("q01.zig").NG_TP_SIZE;
const NG_WRITE_STREAM_FLAG_FIN = @import("q01.zig").NG_WRITE_STREAM_FLAG_FIN;
const NG_WRITE_STREAM_FLAG_MORE = @import("q01.zig").NG_WRITE_STREAM_FLAG_MORE;
const NgApi = @import("q01.zig").NgApi;
const NgCallbacks = @import("q01.zig").NgCallbacks;
const NgCid = @import("q01.zig").NgCid;
const NgCloseError = @import("q01.zig").NgCloseError;
const NgConn = @import("q01.zig").NgConn;
const NgPktInfo = @import("q01.zig").NgPktInfo;
const NgVec = @import("q01.zig").NgVec;
const QuicConn = @import("q01.zig").QuicConn;
const QuicEndpoint = @import("q01.zig").QuicEndpoint;
const QuicListener = @import("q01.zig").QuicListener;
const RawStream = @import("q01.zig").RawStream;
const SA_STD_ERR_INVALID_ARGUMENT = @import("q01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("q01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("q01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("q01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("q01.zig").SA_STD_OK;
const SockAddrIn = @import("q01.zig").SockAddrIn;
const SockStorage = @import("q01.zig").SockStorage;
const cbGetNewConnectionId = @import("q01.zig").cbGetNewConnectionId;
const cbRand = @import("q01.zig").cbRand;
const cryptoGetConn = @import("q01.zig").cryptoGetConn;
const loadGnuApi = @import("q01.zig").loadGnuApi;
const loadNgApi = @import("q01.zig").loadNgApi;
const nowNs = @import("q01.zig").nowNs;
const quicStackAvailable = @import("q01.zig").quicStackAvailable;
const toZ = @import("q01.zig").toZ;
const u64ToUsize = @import("q01.zig").u64ToUsize;

pub fn cbHandshakeCompleted(conn: ?*NgConn, user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    qc.handshake_done = true;
    return 0;
}

pub fn cbRecvStreamData(conn: ?*NgConn, flags: u32, stream_id: i64, offset: u64, data: [*]const u8, datalen: usize, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
    _ = offset;
    _ = stream_user_data;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    const ng = loadNgApi() orelse return -1;
    if (qc.h3) |sess| {
        return sess.feedStreamData(stream_id, data[0..datalen], flags & NG_STREAM_DATA_FLAG_FIN != 0);
    }
    const s = qc.ensureStream(stream_id) catch return -1;
    s.recv.appendSlice(std.heap.page_allocator, data[0..datalen]) catch return -1;
    if (flags & NG_STREAM_DATA_FLAG_FIN != 0) s.recv_fin = true;
    if (datalen > 0) {
        ng.conn_extend_max_stream_offset(conn, stream_id, datalen);
        ng.conn_extend_max_offset(conn, datalen);
    }
    return 0;
}

pub fn cbAckedStreamData(conn: ?*NgConn, stream_id: i64, offset: u64, datalen: u64, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = offset;
    _ = stream_user_data;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    if (qc.h3) |sess| return sess.ackedStreamData(stream_id, datalen);
    return 0;
}

pub fn cbStreamClose(conn: ?*NgConn, flags: u32, stream_id: i64, app_error_code: u64, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = flags;
    _ = stream_user_data;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    if (qc.getStream(stream_id)) |s| s.closed = true;
    if (qc.h3) |sess| return sess.streamClosed(stream_id, app_error_code);
    return 0;
}

pub fn makeCallbacks(ng: *NgApi, qc: *QuicConn) NgCallbacks {
    var cbs = NgCallbacks{ .fields = @splat(null) };
    if (qc.is_server) {
        cbs.fields[CB_RECV_CLIENT_INITIAL] = ng.cb_recv_client_initial;
    } else {
        cbs.fields[CB_CLIENT_INITIAL] = ng.cb_client_initial;
    }
    cbs.fields[CB_RECV_CRYPTO_DATA] = ng.cb_recv_crypto_data;
    cbs.fields[CB_RECV_RETRY] = ng.cb_recv_retry;
    cbs.fields[CB_ENCRYPT] = ng.cb_encrypt;
    cbs.fields[CB_DECRYPT] = ng.cb_decrypt;
    cbs.fields[CB_HP_MASK] = ng.cb_hp_mask;
    cbs.fields[CB_UPDATE_KEY] = ng.cb_update_key;
    cbs.fields[CB_DELETE_CRYPTO_AEAD_CTX] = ng.cb_delete_aead_ctx;
    cbs.fields[CB_DELETE_CRYPTO_CIPHER_CTX] = ng.cb_delete_cipher_ctx;
    cbs.fields[CB_GET_PATH_CHALLENGE_DATA] = ng.cb_get_path_challenge_data;
    cbs.fields[CB_VERSION_NEGOTIATION] = ng.cb_version_negotiation;
    cbs.fields[CB_HANDSHAKE_COMPLETED] = @ptrCast(&cbHandshakeCompleted);
    cbs.fields[CB_RECV_STREAM_DATA] = @ptrCast(&cbRecvStreamData);
    cbs.fields[CB_ACKED_STREAM_DATA_OFFSET] = @ptrCast(&cbAckedStreamData);
    cbs.fields[CB_STREAM_CLOSE] = @ptrCast(&cbStreamClose);
    cbs.fields[CB_RAND] = @ptrCast(&cbRand);
    cbs.fields[CB_GET_NEW_CONNECTION_ID] = @ptrCast(&cbGetNewConnectionId);
    return cbs;
}

pub fn writeTpField(tp: []u8, off: usize, v: u64) void {
    std.mem.writeInt(u64, tp[off..][0..8], v, .little);
}

pub fn buildSettings(ng: *NgApi, ts: u64) [NG_SETTINGS_SIZE]u8 {
    var b: [NG_SETTINGS_SIZE]u8 = @splat(0);
    ng.settings_default(1, &b);
    std.mem.writeInt(u64, b[NG_SETTINGS_OFF_INITIAL_TS..][0..8], ts, .little);
    return b;
}

pub fn buildTransportParams(ng: *NgApi, original_dcid: ?NgCid) [NG_TP_SIZE]u8 {
    var b: [NG_TP_SIZE]u8 = @splat(0);
    ng.transport_params_default(1, &b);
    writeTpField(&b, NG_TP_OFF_MAX_STREAM_DATA_BIDI_LOCAL, 1_048_576);
    writeTpField(&b, NG_TP_OFF_MAX_STREAM_DATA_BIDI_REMOTE, 1_048_576);
    writeTpField(&b, NG_TP_OFF_MAX_STREAM_DATA_UNI, 262_144);
    writeTpField(&b, NG_TP_OFF_MAX_DATA, 4_194_304);
    writeTpField(&b, NG_TP_OFF_MAX_STREAMS_BIDI, 100);
    writeTpField(&b, NG_TP_OFF_MAX_STREAMS_UNI, 100);
    writeTpField(&b, NG_TP_OFF_MAX_IDLE_TIMEOUT, 30_000_000_000);
    writeTpField(&b, NG_TP_OFF_ACTIVE_CID_LIMIT, 4);
    if (original_dcid) |cid| {
        std.mem.writeInt(u64, b[NG_TP_OFF_ORIGINAL_DCID..][0..8], cid.datalen, .little);
        @memcpy(b[NG_TP_OFF_ORIGINAL_DCID + 8 ..][0..20], &cid.data);
    }
    return b;
}

// ---- UDP + address helpers ------------------------------------------------------
pub fn parseIp4Literal(host: []const u8, port: u16) ?SockAddrIn {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return parseIp4LiteralNative(host, port);
    }
}

pub fn parseIp4LiteralNative(host: []const u8, port: u16) ?SockAddrIn {
    var addr: u32 = 0;
    var part: u32 = 0;
    var dots: usize = 0;
    var digits: usize = 0;
    for (host) |ch| {
        if (ch == '.') {
            if (digits == 0 or part > 255) return null;
            addr = (addr << 8) | part;
            part = 0;
            digits = 0;
            dots += 1;
        } else if (ch >= '0' and ch <= '9') {
            part = part * 10 + (ch - '0');
            digits += 1;
        } else return null;
    }
    if (dots != 3 or digits == 0 or part > 255) return null;
    addr = (addr << 8) | part;
    return .{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, addr),
    };
}

pub fn lxClose(fd: i32) void {
    if (comptime builtin.cpu.arch.isWasm()) {
    } else {
        _ = std.os.linux.close(fd);
    }
}

pub fn lxSendTo(fd: i32, buf: [*]const u8, len: usize, flags: u32, dest: ?*const SockStorage, dest_len: std.posix.socklen_t) isize {
    if (comptime builtin.cpu.arch.isWasm()) {
        return -1;
    } else {
        return @bitCast(std.os.linux.sendto(fd, buf, len, flags, @ptrCast(dest), dest_len));
    }
}

pub fn lxConnect(fd: i32, storage: *const SockStorage, len: std.posix.socklen_t) isize {
    if (comptime builtin.cpu.arch.isWasm()) {
        return -1;
    } else {
        return @bitCast(std.os.linux.connect(fd, @ptrCast(storage), len));
    }
}

pub fn lxBind(fd: i32, storage: *const SockStorage, len: std.posix.socklen_t) isize {
    if (comptime builtin.cpu.arch.isWasm()) {
        return -1;
    } else {
        return @bitCast(std.os.linux.bind(fd, @ptrCast(storage), len));
    }
}

pub fn lxRecvFrom(fd: i32, buf: [*]u8, len: usize, flags: u32, src: ?*SockStorage, src_len: ?*std.posix.socklen_t) isize {
    if (comptime builtin.cpu.arch.isWasm()) {
        return -1;
    } else {
        return @bitCast(std.os.linux.recvfrom(fd, buf, len, flags, @ptrCast(src), src_len));
    }
}

pub fn resolveIp4(host: []const u8, port: u16) !SockAddrIn {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return resolveIp4Native(host, port);
    }
}

pub fn resolveIp4Native(host: []const u8, port: u16) !SockAddrIn {
    if (parseIp4Literal(host, port)) |a| return a;
    if (std.mem.eql(u8, host, "localhost")) return parseIp4Literal("127.0.0.1", port).?;
    const host_z = toZ(std.heap.page_allocator, host) orelse return error.OutOfMemory;
    defer std.heap.page_allocator.free(host_z);
    var port_buf: [8]u8 = undefined;
    const port_s = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch unreachable;
    const port_z = toZ(std.heap.page_allocator, port_s) orelse return error.OutOfMemory;
    defer std.heap.page_allocator.free(port_z);
    var hints: std.c.addrinfo = std.mem.zeroes(std.c.addrinfo);
    hints.family = std.posix.AF.INET;
    hints.socktype = std.posix.SOCK.DGRAM;
    hints.protocol = std.posix.IPPROTO.UDP;
    var res: ?*std.c.addrinfo = null;
    if (@intFromEnum(std.c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res)) != 0) return error.UnknownHost;
    defer if (res) |r| std.c.freeaddrinfo(r);
    const first = res orelse return error.UnknownHost;
    const sa: *const std.posix.sockaddr.in = @ptrCast(@alignCast(first.addr orelse return error.UnknownHost));
    return sa.*;
}

pub fn storageFromIn(sa: SockAddrIn) struct { storage: SockStorage, len: std.posix.socklen_t } {
    var storage: SockStorage = undefined;
    @memcpy(std.mem.asBytes(&storage)[0..@sizeOf(SockAddrIn)], std.mem.asBytes(&sa));
    return .{ .storage = storage, .len = @sizeOf(SockAddrIn) };
}

pub fn udpSocket() !std.posix.fd_t {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return udpSocketNative();
    }
}

pub fn udpSocketNative() !std.posix.fd_t {
    const rc = std.os.linux.socket(std.posix.AF.INET, std.os.linux.SOCK.DGRAM | std.os.linux.SOCK.CLOEXEC | std.os.linux.SOCK.NONBLOCK, 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.SocketFailed;
    return @intCast(rc);
}

pub fn socketLocalAddr(fd: std.posix.fd_t, out: *SockStorage, out_len: *std.posix.socklen_t) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return socketLocalAddrNative(fd, out, out_len);
    }
}

pub fn socketLocalAddrNative(fd: std.posix.fd_t, out: *SockStorage, out_len: *std.posix.socklen_t) !void {
    out_len.* = @sizeOf(SockStorage);
    const rc = std.os.linux.getsockname(fd, @ptrCast(out), out_len);
    if (@as(isize, @bitCast(rc)) < 0) return error.GetsocknameFailed;
}

// ---- GnuTLS session setup --------------------------------------------------------
pub const GNUTLS_ALPN_H3 = "h3";

pub fn gnuSetAlpn(ga: *GnuApi, session: *GnuSession, alpn: []const u8) !void {
    var datums = [1]GnuDatum{.{ .data = @constCast(alpn.ptr), .size = @intCast(alpn.len) }};
    if (ga.alpn_set_protocols(session, &datums, 1, GNUTLS_ALPN_MANDATORY) != 0) return error.AlpnFailed;
}

pub fn gnuClientSession(ga: *GnuApi, ng: *NgApi, qc: *QuicConn, server_name: []const u8, ca_file: ?[]const u8, alpn: []const u8) !void {
    var cred: ?*GnuCred = null;
    if (ga.cert_allocate(&cred) != 0) return error.GnuInit;
    errdefer ga.cert_free(cred);
    if (ca_file) |caf| {
        const z = toZ(std.heap.page_allocator, caf) orelse return error.OutOfMemory;
        defer std.heap.page_allocator.free(z);
        if (ga.cert_trust_file(cred, z.ptr, GNUTLS_X509_FMT_PEM) < 0) return error.GnuTrust;
    } else {
        if (ga.cert_system_trust(cred) < 0) return error.GnuTrust;
    }
    var session: ?*GnuSession = null;
    if (ga.init(&session, GNUTLS_CLIENT) != 0) return error.GnuInit;
    errdefer ga.deinit(session);
    if (ng.crypto_configure_client(session) != 0) return error.GnuConfigure;
    if (ga.priority_set_direct(session, GTLS_PRIORITY, null) != 0) return error.GnuPriority;
    ga.session_set_ptr(session, &qc.conn_ref);
    if (ga.credentials_set(session, GNUTLS_CRD_CERTIFICATE, cred) != 0) return error.GnuCredSet;
    try gnuSetAlpn(ga, session.?, alpn);
    if (server_name.len > 0) {
        _ = ga.server_name_set(session, GNUTLS_NAME_DNS, server_name.ptr, server_name.len);
        // NOTE: gnutls_session_set_verify_cert keeps the hostname
        // pointer for the session's whole lifetime (it is strlen'd
        // during the handshake) — it must outlive the session, so it
        // is owned by the connection, not freed here.
        const nz = toZ(std.heap.page_allocator, server_name) orelse return error.OutOfMemory;
        qc.sni_z = nz;
        ga.session_set_verify_cert(session, nz.ptr, 0);
    }
    qc.session = session;
    qc.cred = cred;
}

pub fn gnuServerSession(ga: *GnuApi, ng: *NgApi, qc: *QuicConn, shared_cred: *GnuCred, alpn: []const u8) !void {
    var session: ?*GnuSession = null;
    if (ga.init(&session, GNUTLS_SERVER) != 0) return error.GnuInit;
    errdefer ga.deinit(session);
    if (ng.crypto_configure_server(session) != 0) return error.GnuConfigure;
    if (ga.priority_set_direct(session, GTLS_PRIORITY, null) != 0) return error.GnuPriority;
    ga.session_set_ptr(session, &qc.conn_ref);
    if (ga.credentials_set(session, GNUTLS_CRD_CERTIFICATE, shared_cred) != 0) return error.GnuCredSet;
    try gnuSetAlpn(ga, session.?, alpn);
    qc.session = session;
}

// ---- packet flushing --------------------------------------------------------------
pub const PKT_BUF = 1452;

pub const H3_WRITE_BLOCKED: i64 = -2_000_000_002;

pub fn flushWrites(qc: *QuicConn) void {
    const ng = loadNgApi() orelse return;
    const conn = qc.conn orelse return;
    var buf: [PKT_BUF]u8 = undefined;
    var guard: usize = 0;
    while (guard < 512) : (guard += 1) {
        var p = qc.path();
        var pi = NgPktInfo{ .ecn = 0 };
        var wdatalen: i64 = 0;
        var nwrite: i64 = -1;

        if (qc.h3) |sess| {
            nwrite = sess.writeStep(&p, &pi, &buf, &wdatalen);
            if (nwrite == H3_WRITE_BLOCKED) {
                // nghttp3 has nothing writable; still emit ACK/control.
                nwrite = ng.conn_writev_stream(conn, &p, 1, &pi, &buf, buf.len, &wdatalen, 0, -1, null, 0, nowNs());
            } else if (nwrite < 0) {
                break;
            }
        } else {
            // A FIN that ngtcp2 already consumed into a pending packet
            // (WRITE_MORE) must be completed with a no-stream
            // continuation call; re-offering the stream fails with
            // NGTCP2_ERR_STREAM_SHUT_WR.
            var sid: i64 = -1;
            var target: ?*RawStream = null;
            var cont: ?*RawStream = null;
            {
                var it = qc.streams.iterator();
                while (it.next()) |e| {
                    if (e.value_ptr.*.fin_in_pending) {
                        cont = e.value_ptr.*;
                        break;
                    }
                }
            }
            var datav: [1]NgVec = .{.{ .base = null, .len = 0 }};
            var datav_ptr: ?[*]const NgVec = null;
            var datav_cnt: usize = 0;
            var flags: u32 = NG_WRITE_STREAM_FLAG_MORE;
            var offered_len: usize = 0;
            if (cont == null) {
                var it = qc.streams.iterator();
                while (it.next()) |e| {
                    const st = e.value_ptr.*;
                    if (st.send_done) continue;
                    const remaining = st.send.items.len - st.send_off;
                    if (remaining > 0) {
                        sid = e.key_ptr.*;
                        target = st;
                        datav[0] = .{ .base = st.send.items.ptr + st.send_off, .len = remaining };
                        datav_ptr = &datav;
                        datav_cnt = 1;
                        offered_len = remaining;
                        if (st.send_fin) flags |= NG_WRITE_STREAM_FLAG_FIN;
                        break;
                    } else if (st.send_fin and !st.fin_in_pending) {
                        sid = e.key_ptr.*;
                        target = st;
                        datav[0] = .{ .base = null, .len = 0 };
                        datav_ptr = &datav;
                        datav_cnt = 1;
                        flags = NG_WRITE_STREAM_FLAG_FIN;
                        break;
                    }
                }
            }
            nwrite = ng.conn_writev_stream(conn, &p, 1, &pi, &buf, buf.len, &wdatalen, flags, sid, datav_ptr, datav_cnt, nowNs());
            if (nwrite == NG_ERR_WRITE_MORE) {
                if (target) |st| {
                    if (wdatalen > 0) st.send_off += @intCast(wdatalen);
                    if ((flags & NG_WRITE_STREAM_FLAG_FIN) != 0 and wdatalen >= offered_len) st.fin_in_pending = true;
                }
                continue;
            }
            if (nwrite > 0) {
                if (cont) |cst| {
                    cst.fin_in_pending = false;
                    cst.send_done = true;
                } else if (target) |st| {
                    if (wdatalen > 0) st.send_off += @intCast(wdatalen);
                    if ((flags & NG_WRITE_STREAM_FLAG_FIN) != 0 and st.send_off >= st.send.items.len) st.send_done = true;
                }
            }
        }

        if (nwrite <= 0) break;
        qc.sendPacket(buf[0..@intCast(nwrite)]);
    }
}

// ---- constructors -------------------------------------------------------------------
pub fn strArg(ptr_: ?[*]const u8, len: u64) ?[]const u8 {
    const n = u64ToUsize(len) orelse return null;
    if (ptr_) |p| return p[0..n];
    return if (n == 0) "" else null;
}

pub export fn sa_std_quic_endpoint_create(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (!quicStackAvailable()) return SA_STD_ERR_UNSUPPORTED;
    const ep = std.heap.page_allocator.create(QuicEndpoint) catch return SA_STD_ERR_NO_MEMORY;
    ep.* = .{};
    slot.* = @intFromPtr(ep);
    return SA_STD_OK;
}

pub export fn sa_std_quic_endpoint_destroy(handle: u64) i32 {
    if (handle == 0) return SA_STD_OK;
    const ep: *QuicEndpoint = @ptrFromInt(@as(usize, @intCast(handle)));
    if (ep.listener) |l| destroyListener(l);
    std.heap.page_allocator.destroy(ep);
    return SA_STD_OK;
}

pub fn endpointFrom(handle: u64) ?*QuicEndpoint {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

pub fn connFrom(handle: u64) ?*QuicConn {
    if (handle == 0) return null;
    const p: *QuicConn = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_quic_client_connect(endpoint: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, server_name_ptr: ?[*]const u8, server_name_len: u64, ca_file_ptr: ?[*]const u8, ca_file_len: u64, alpn_ptr: ?[*]const u8, alpn_len: u64, out_conn: ?*u64) i32 {
    _ = endpoint;
    const slot = out_conn orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ga = loadGnuApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const host = strArg(host_ptr, host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (host.len == 0 or port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;
    const server_name = strArg(server_name_ptr, server_name_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ca_file = strArg(ca_file_ptr, ca_file_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const alpn = strArg(alpn_ptr, alpn_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const alpn_eff: []const u8 = if (alpn.len == 0) GNUTLS_ALPN_H3 else alpn;
    const sni: []const u8 = if (server_name.len == 0) host else server_name;

    const addr = resolveIp4(host, @intCast(port)) catch return SA_STD_ERR_IO;
    const fd = udpSocket() catch return SA_STD_ERR_IO;
    errdefer lxClose(fd);
    const peer_st = storageFromIn(addr);
    if (lxConnect(fd, &peer_st.storage, peer_st.len) < 0) return SA_STD_ERR_IO;

    const qc = std.heap.page_allocator.create(QuicConn) catch return SA_STD_ERR_NO_MEMORY;
    errdefer std.heap.page_allocator.destroy(qc);
    qc.* = .{ .fd = fd, .owns_fd = true, .is_server = false };
    qc.peer = peer_st.storage;
    qc.peer_len = peer_st.len;
    socketLocalAddr(fd, &qc.local, &qc.local_len) catch return SA_STD_ERR_IO;
    qc.conn_ref = .{ .get_conn = &cryptoGetConn, .user_data = qc };

    gnuClientSession(ga, ng, qc, sni, if (ca_file.len == 0) null else ca_file, alpn_eff) catch return SA_STD_ERR_IO;

    var dcid: NgCid = .{ .datalen = 8, .data = @splat(0) };
    sio.io().random(dcid.data[0..8]);
    var scid: NgCid = .{ .datalen = 8, .data = @splat(0) };
    sio.io().random(scid.data[0..8]);
    @memcpy(&qc.scid, scid.data[0..8]);

    const cbs = makeCallbacks(ng, qc);
    const settings = buildSettings(ng, nowNs());
    const tp = buildTransportParams(ng, null);
    var p = qc.path();
    var conn: ?*NgConn = null;
    if (ng.conn_client_new(&conn, &dcid, &scid, &p, NG_PROTO_VER_V1, 1, &cbs, 1, &settings, 1, &tp, null, qc) != 0) {
        if (qc.session) |sess| ga.deinit(sess);
        if (qc.cred) |c| ga.cert_free(c);
        lxClose(fd);
        std.heap.page_allocator.destroy(qc);
        return SA_STD_ERR_IO;
    }
    qc.conn = conn;
    ng.conn_set_tls_native_handle(conn, qc.session);

    flushWrites(qc);
    slot.* = @intFromPtr(qc);
    return SA_STD_OK;
}

pub export fn sa_std_quic_server_listen(endpoint: u64, port: u32, cert_ptr: ?[*]const u8, cert_len: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const ep = endpointFrom(endpoint) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (ep.listener != null) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;
    const ga = loadGnuApi() orelse return SA_STD_ERR_UNSUPPORTED;
    if (loadNgApi() == null) return SA_STD_ERR_UNSUPPORTED;
    const cert = strArg(cert_ptr, cert_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const key = strArg(key_ptr, key_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (cert.len == 0 or key.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;

    var cred: ?*GnuCred = null;
    if (ga.cert_allocate(&cred) != 0) return SA_STD_ERR_IO;
    errdefer ga.cert_free(cred);
    const cert_z = toZ(std.heap.page_allocator, cert) orelse return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(cert_z);
    const key_z = toZ(std.heap.page_allocator, key) orelse return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(key_z);
    if (ga.cert_key_file(cred, cert_z.ptr, key_z.ptr, GNUTLS_X509_FMT_PEM) < 0) return SA_STD_ERR_IO;

    const fd = udpSocket() catch return SA_STD_ERR_IO;
    errdefer lxClose(fd);
    const bind_addr = parseIp4Literal("0.0.0.0", @intCast(port)).?;
    const bs = storageFromIn(bind_addr);
    if (lxBind(fd, &bs.storage, bs.len) < 0) return SA_STD_ERR_IO;

    const l = std.heap.page_allocator.create(QuicListener) catch return SA_STD_ERR_NO_MEMORY;
    l.* = .{ .fd = fd, .cred = cred };
    socketLocalAddr(fd, &l.local, &l.local_len) catch {
        std.heap.page_allocator.destroy(l);
        return SA_STD_ERR_IO;
    };
    ep.listener = l;
    return SA_STD_OK;
}

pub fn destroyListener(l: *QuicListener) void {
    const ng = loadNgApi();
    const ga = loadGnuApi();
    for (l.conns.items) |qc| destroyConn(qc, false);
    l.conns.deinit(std.heap.page_allocator);
    l.pending.deinit(std.heap.page_allocator);
    l.route.deinit(std.heap.page_allocator);
    if (l.cred) |c| {
        if (ga) |g| g.cert_free(c);
    }
    _ = ng;
    lxClose(l.fd);
    std.heap.page_allocator.destroy(l);
}

pub fn destroyConn(qc: *QuicConn, send_close: bool) void {
    const ng = loadNgApi();
    const ga = loadGnuApi();
    if (qc.h3) |sess| sess.destroy();
    if (qc.conn) |conn| {
        if (send_close) {
            if (ng) |n| {
                var p = qc.path();
                var pi = NgPktInfo{ .ecn = 0 };
                var buf: [PKT_BUF]u8 = undefined;
                const ccerr = NgCloseError{ .type_ = 0, .error_code = 0, .frame_type = 0, .reason = null, .reasonlen = 0 };
                const nw = n.conn_write_connection_close(conn, &p, 1, &pi, &buf, buf.len, &ccerr, nowNs());
                if (nw > 0) qc.sendPacket(buf[0..@intCast(nw)]);
            }
        }
        if (ng) |n| n.conn_del(conn);
    }
    if (qc.session) |s| {
        if (ga) |g| g.deinit(s);
    }
    if (qc.sni_z) |z| std.heap.page_allocator.free(z);
    if (qc.cred) |c| {
        if (ga) |g| g.cert_free(c);
    }
    var it = qc.streams.valueIterator();
    while (it.next()) |sp| {
        sp.*.recv.deinit(std.heap.page_allocator);
        sp.*.send.deinit(std.heap.page_allocator);
        std.heap.page_allocator.destroy(sp.*);
    }
    qc.streams.deinit(std.heap.page_allocator);
    if (qc.owns_fd) lxClose(qc.fd);
    std.heap.page_allocator.destroy(qc);
}

pub export fn sa_std_quic_conn_close(handle: u64) i32 {
    const qc = connFrom(handle) orelse return SA_STD_OK;
    if (qc.listener) |l| {
        // detach from listener bookkeeping
        for (l.conns.items, 0..) |c, i| {
            if (c == qc) {
                _ = l.conns.orderedRemove(i);
                break;
            }
        }
        const key = std.mem.readInt(u64, &qc.scid, .big);
        _ = l.route.remove(key);
    }
    destroyConn(qc, true);
    return SA_STD_OK;
}

pub export fn sa_std_quic_conn_handshake_completed(handle: u64, out: ?*u32) i32 {
    const slot = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (qc.handshake_done) 1 else 0;
    return SA_STD_OK;
}
