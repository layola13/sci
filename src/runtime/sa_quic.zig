// QUIC + HTTP/3 runtime for the sci/sa_std platform layer.
//
// Real protocol machines, dlopen-bound (the pattern used by sa_http2.zig,
// sa_tls_server.zig, sa_tls_shaped.zig):
//   * QUIC transport: libngtcp2 (callbacks + versioned entry points,
//     ABI verified against ngtcp2 0.12 headers: struct sizes/offsets
//     measured with a C offsetof probe, not guessed).
//   * TLS 1.3 for QUIC: the ngtcp2 GnuTLS crypto backend
//     (libngtcp2_crypto_gnutls + libgnutls). This is the backend Ubuntu
//     ships; it needs no OpenSSL QUIC API (system OpenSSL 3.0 has none).
//   * HTTP/3: libnghttp3, glued to the QUIC streams below.
//
// Capability gating stays honest: sa_std_quic_supported reports 1 only
// when every required library AND symbol resolves at runtime. Hosts
// without the stack get UNSUPPORTED from the constructors, never a
// fabricated session.
//
// Driving model: connections are non-blocking and caller-pumped.
// sa_std_quic_conn_poll / sa_std_quic_server_poll drain datagrams, run
// ngtcp2 timers, and flush pending packets. One pump loop per endpoint
// is enough for a full handshake + HTTP/3 exchange (the loopback tests
// drive client and server from a single thread).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_AGAIN: i32 = -11;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;

fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

fn nowNs() u64 {
    const v = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (v <= 0) return 0;
    return @intCast(@min(v, @as(i96, std.math.maxInt(u64))));
}

fn toZ(alloc: std.mem.Allocator, text: []const u8) ?[:0]u8 {
    const z = alloc.allocSentinel(u8, text.len, 0) catch return null;
    @memcpy(z, text);
    return z;
}

// ---- ngtcp2 ABI (verified against ngtcp2 0.12.1 headers) -------------------

const NgConn = opaque {};
const NgCid = extern struct {
    datalen: usize,
    data: [20]u8,
};
const NgVec = extern struct {
    base: ?[*]u8,
    len: usize,
};
const NgSockaddr = std.posix.sockaddr;
const NgAddr = extern struct {
    addr: ?*NgSockaddr,
    addrlen: usize,
};
const NgPath = extern struct {
    local: NgAddr,
    remote: NgAddr,
    user_data: ?*anyopaque = null,
};
const NgPktInfo = extern struct {
    ecn: u8,
    _pad: [7]u8 = @splat(0),
};
const NgCloseError = extern struct {
    type_: u32,
    _pad0: u32 = 0,
    error_code: u64,
    frame_type: u64,
    reason: ?[*]const u8,
    reasonlen: usize,
};
const NgCryptoConnRef = extern struct {
    get_conn: *const fn (?*NgCryptoConnRef) callconv(.c) ?*NgConn,
    user_data: ?*anyopaque,
};
const NgPktHd = extern struct {
    dcid: NgCid, // @0
    scid: NgCid, // @32
    token: NgVec, // @64
    _mid: [24]u8 = @splat(0), // pkt_num view + lengths, unused here
    version: u32, // @104
    type_: u8, // @108
    _pad: [3]u8 = @splat(0),
}; // sizeof = 112, C-verified

// ngtcp2_settings: 184 bytes; ngtcp2_transport_params: 344 bytes. The
// versioned *_default functions fill them; we then write the fields we
// customize at C-probe-verified byte offsets.
const NG_SETTINGS_SIZE = 184;
const NG_SETTINGS_OFF_INITIAL_TS = 48;
const NG_TP_SIZE = 344;
const NG_TP_OFF_ORIGINAL_DCID = 96;
const NG_TP_OFF_MAX_STREAM_DATA_BIDI_LOCAL = 192;
const NG_TP_OFF_MAX_STREAM_DATA_BIDI_REMOTE = 200;
const NG_TP_OFF_MAX_STREAM_DATA_UNI = 208;
const NG_TP_OFF_MAX_DATA = 216;
const NG_TP_OFF_MAX_STREAMS_BIDI = 224;
const NG_TP_OFF_MAX_STREAMS_UNI = 232;
const NG_TP_OFF_MAX_IDLE_TIMEOUT = 240;
const NG_TP_OFF_ACTIVE_CID_LIMIT = 256;

const NG_CALLBACKS_COUNT = 40;
const NgCallbacks = extern struct {
    fields: [NG_CALLBACKS_COUNT]?*const anyopaque,
};
// callback slot indices (V1 layout, offsets verified by C probe)
const CB_CLIENT_INITIAL = 0;
const CB_RECV_CLIENT_INITIAL = 1;
const CB_RECV_CRYPTO_DATA = 2;
const CB_HANDSHAKE_COMPLETED = 3;
const CB_ENCRYPT = 5;
const CB_DECRYPT = 6;
const CB_HP_MASK = 7;
const CB_RECV_STREAM_DATA = 8;
const CB_ACKED_STREAM_DATA_OFFSET = 9;
const CB_STREAM_CLOSE = 11;
const CB_RECV_RETRY = 13;
const CB_RAND = 16;
const CB_GET_NEW_CONNECTION_ID = 17;
const CB_UPDATE_KEY = 19;
const CB_DELETE_CRYPTO_AEAD_CTX = 29;
const CB_DELETE_CRYPTO_CIPHER_CTX = 30;
const CB_GET_PATH_CHALLENGE_DATA = 34;
const CB_VERSION_NEGOTIATION = 36;

const RecvStreamDataFn = *const fn (?*NgConn, u32, i64, u64, [*]const u8, usize, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const AckedStreamDataFn = *const fn (?*NgConn, i64, u64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const StreamCloseFn = *const fn (?*NgConn, u32, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const HandshakeCompletedFn = *const fn (?*NgConn, ?*anyopaque) callconv(.c) c_int;
const RandFn = *const fn ([*]u8, usize, ?*const anyopaque) callconv(.c) void;
const GetNewConnectionIdFn = *const fn (?*NgConn, ?*NgCid, [*]u8, usize, ?*anyopaque) callconv(.c) c_int;

const NG_WRITE_STREAM_FLAG_MORE: u32 = 0x01;
const NG_WRITE_STREAM_FLAG_FIN: u32 = 0x02;
const NG_STREAM_DATA_FLAG_FIN: u32 = 0x01;
const NG_ERR_WRITE_MORE: i64 = -240;
const NG_PROTO_VER_V1: u32 = 0x0000_0001;
const NG_MAX_CIDLEN = 20;

const NgApi = struct {
    lib: std.DynLib,
    crypto_lib: std.DynLib,
    conn_client_new: *const fn (*?*NgConn, *const NgCid, *const NgCid, *const NgPath, u32, c_int, *const NgCallbacks, c_int, *const anyopaque, c_int, *const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    conn_server_new: *const fn (*?*NgConn, *const NgCid, *const NgCid, *const NgPath, u32, c_int, *const NgCallbacks, c_int, *const anyopaque, c_int, *const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    conn_del: *const fn (?*NgConn) callconv(.c) void,
    conn_read_pkt: *const fn (?*NgConn, *const NgPath, c_int, *const NgPktInfo, [*]const u8, usize, u64) callconv(.c) c_int,
    conn_writev_stream: *const fn (?*NgConn, ?*NgPath, c_int, ?*NgPktInfo, [*]u8, usize, ?*i64, u32, i64, ?[*]const NgVec, usize, u64) callconv(.c) i64,
    conn_write_connection_close: *const fn (?*NgConn, ?*NgPath, c_int, ?*NgPktInfo, [*]u8, usize, *const NgCloseError, u64) callconv(.c) i64,
    conn_open_bidi_stream: *const fn (?*NgConn, *i64, ?*anyopaque) callconv(.c) c_int,
    conn_open_uni_stream: *const fn (?*NgConn, *i64, ?*anyopaque) callconv(.c) c_int,
    conn_get_expiry: *const fn (?*NgConn) callconv(.c) u64,
    conn_handle_expiry: *const fn (?*NgConn, u64) callconv(.c) c_int,
    conn_set_tls_native_handle: *const fn (?*NgConn, ?*anyopaque) callconv(.c) void,
    conn_extend_max_stream_offset: *const fn (?*NgConn, i64, u64) callconv(.c) void,
    conn_extend_max_offset: *const fn (?*NgConn, u64) callconv(.c) void,
    conn_shutdown_stream_read: *const fn (?*NgConn, i64, u64) callconv(.c) c_int,
    conn_shutdown_stream: *const fn (?*NgConn, i64, u64) callconv(.c) c_int,
    accept: *const fn (*NgPktHd, [*]const u8, usize) callconv(.c) c_int,
    settings_default: *const fn (c_int, *anyopaque) callconv(.c) void,
    transport_params_default: *const fn (c_int, *anyopaque) callconv(.c) void,
    crypto_configure_client: *const fn (?*anyopaque) callconv(.c) c_int,
    crypto_configure_server: *const fn (?*anyopaque) callconv(.c) c_int,
    cb_client_initial: *const anyopaque,
    cb_recv_client_initial: *const anyopaque,
    cb_recv_crypto_data: *const anyopaque,
    cb_recv_retry: *const anyopaque,
    cb_encrypt: *const anyopaque,
    cb_decrypt: *const anyopaque,
    cb_hp_mask: *const anyopaque,
    cb_update_key: *const anyopaque,
    cb_delete_aead_ctx: *const anyopaque,
    cb_delete_cipher_ctx: *const anyopaque,
    cb_get_path_challenge_data: *const anyopaque,
    cb_version_negotiation: *const anyopaque,
};

// ---- GnuTLS ABI --------------------------------------------------------------

const GnuSession = opaque {};
const GnuCred = opaque {};
const GnuDatum = extern struct { data: ?[*]u8, size: c_uint };

const GNUTLS_SERVER: c_int = 1;
const GNUTLS_CLIENT: c_int = 2;
const GNUTLS_CRD_CERTIFICATE: c_int = 1;
const GNUTLS_NAME_DNS: c_int = 1;
const GNUTLS_X509_FMT_PEM: c_int = 1;
const GNUTLS_ALPN_MANDATORY: c_uint = 1;

const GTLS_PRIORITY: [*:0]const u8 = "NORMAL:-VERS-ALL:+VERS-TLS1.3:-CIPHER-ALL:+AES-128-GCM:+AES-256-GCM:+CHACHA20-POLY1305:+AES-128-CCM:-GROUP-ALL:+GROUP-SECP256R1:+GROUP-X25519:+GROUP-SECP384R1:+GROUP-SECP521R1:%DISABLE_TLS13_COMPAT_MODE";

const GnuApi = struct {
    lib: std.DynLib,
    init: *const fn (*?*GnuSession, c_int) callconv(.c) c_int,
    deinit: *const fn (?*GnuSession) callconv(.c) void,
    cert_allocate: *const fn (*?*GnuCred) callconv(.c) c_int,
    cert_free: *const fn (?*GnuCred) callconv(.c) void,
    cert_system_trust: *const fn (?*GnuCred) callconv(.c) c_int,
    cert_trust_file: *const fn (?*GnuCred, [*:0]const u8, c_int) callconv(.c) c_int,
    cert_key_file: *const fn (?*GnuCred, [*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int,
    priority_set_direct: *const fn (?*GnuSession, [*:0]const u8, ?*?*const u8) callconv(.c) c_int,
    credentials_set: *const fn (?*GnuSession, c_int, ?*GnuCred) callconv(.c) c_int,
    alpn_set_protocols: *const fn (?*GnuSession, [*]const GnuDatum, c_uint, c_uint) callconv(.c) c_int,
    server_name_set: *const fn (?*GnuSession, c_int, ?*const anyopaque, usize) callconv(.c) c_int,
    session_set_ptr: *const fn (?*GnuSession, ?*anyopaque) callconv(.c) void,
    session_set_verify_cert: *const fn (?*GnuSession, ?[*:0]const u8, c_uint) callconv(.c) void,
};

// ---- nghttp3 ABI (verified against nghttp3 0.8.0 headers) -------------------

const H3Conn = opaque {};
const H3Rcbuf = opaque {};
const H3Vec = extern struct { base: ?[*]u8, len: usize };
const H3Settings = extern struct {
    max_field_section_size: u64,
    qpack_max_dtable_capacity: usize,
    qpack_encoder_max_dtable_capacity: usize,
    qpack_blocked_streams: usize,
    enable_connect_protocol: c_int,
    _pad: u32 = 0,
};
const H3Nv = extern struct {
    name: ?[*]const u8,
    value: ?[*]const u8,
    namelen: usize,
    valuelen: usize,
    flags: u32,
    _pad: u32 = 0,
};
const H3_CALLBACKS_COUNT = 14;
const H3Callbacks = extern struct {
    fields: [H3_CALLBACKS_COUNT]?*const anyopaque,
};
const H3CB_ACKED_STREAM_DATA = 0;
const H3CB_STREAM_CLOSE = 1;
const H3CB_RECV_DATA = 2;
const H3CB_DEFERRED_CONSUME = 3;
const H3CB_BEGIN_HEADERS = 4;
const H3CB_RECV_HEADER = 5;
const H3CB_END_HEADERS = 6;
const H3CB_STOP_SENDING = 10;
const H3CB_END_STREAM = 11;
const H3CB_RESET_STREAM = 12;

const H3AckedFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3StreamCloseFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3RecvDataFn = *const fn (?*H3Conn, i64, [*]const u8, usize, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3BeginHeadersFn = *const fn (?*H3Conn, i64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3RecvHeaderFn = *const fn (?*H3Conn, i64, i32, ?*H3Rcbuf, ?*H3Rcbuf, u8, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3EndHeadersFn = *const fn (?*H3Conn, i64, c_int, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3EndStreamFn = *const fn (?*H3Conn, i64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3StopSendingFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;
const H3ReadDataFn = *const fn (?*H3Conn, i64, [*]H3Vec, usize, *u32, ?*anyopaque, ?*anyopaque) callconv(.c) i64;
const H3DataReader = extern struct { read_data: ?H3ReadDataFn };

const H3_NV_FLAG_NONE: u32 = 0;
const H3_DATA_FLAG_EOF: u32 = 0x01;

const H3Api = struct {
    lib: std.DynLib,
    conn_client_new: *const fn (*?*H3Conn, c_int, *const H3Callbacks, c_int, *const H3Settings, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    conn_server_new: *const fn (*?*H3Conn, c_int, *const H3Callbacks, c_int, *const H3Settings, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    conn_del: *const fn (?*H3Conn) callconv(.c) void,
    bind_control_stream: *const fn (?*H3Conn, i64) callconv(.c) c_int,
    bind_qpack_streams: *const fn (?*H3Conn, i64, i64) callconv(.c) c_int,
    read_stream: *const fn (?*H3Conn, i64, [*]const u8, usize, c_int) callconv(.c) i64,
    writev_stream: *const fn (?*H3Conn, ?*i64, ?*c_int, ?[*]H3Vec, usize) callconv(.c) i64,
    add_write_offset: *const fn (?*H3Conn, i64, usize) callconv(.c) c_int,
    add_ack_offset: *const fn (?*H3Conn, i64, u64) callconv(.c) c_int,
    submit_request: *const fn (?*H3Conn, i64, [*]const H3Nv, usize, ?*const H3DataReader, ?*anyopaque) callconv(.c) c_int,
    submit_response: *const fn (?*H3Conn, i64, [*]const H3Nv, usize, ?*const H3DataReader) callconv(.c) c_int,
    close_stream: *const fn (?*H3Conn, i64, u64) callconv(.c) c_int,
    resume_stream: *const fn (?*H3Conn, i64) callconv(.c) c_int,
    block_stream: *const fn (?*H3Conn, i64) callconv(.c) c_int,
    set_stream_user_data: *const fn (?*H3Conn, i64, ?*anyopaque) callconv(.c) c_int,
    rcbuf_get_buf: *const fn (?*const H3Rcbuf) callconv(.c) H3Vec,
};

// ---- dlopen loaders -----------------------------------------------------------

var ng_api: ?NgApi = null;
var gnu_api: ?GnuApi = null;
var h3_api: ?H3Api = null;
var api_mutex = std.Io.Mutex.init;

fn openFirst(candidates: []const []const u8) ?std.DynLib {
    for (candidates) |c| {
        if (std.DynLib.open(c)) |lib| return lib else |_| {}
    }
    return null;
}

fn loadNgApi() ?*NgApi {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    api_mutex.lockUncancelable(sio.io());
    defer api_mutex.unlock(sio.io());
    if (ng_api) |*a| return a;
    var lib = openFirst(&.{ "libngtcp2.so.9", "libngtcp2.so.16", "libngtcp2.so", "/usr/lib/x86_64-linux-gnu/libngtcp2.so.9", "/lib/x86_64-linux-gnu/libngtcp2.so.9" }) orelse return null;
    var crypto = openFirst(&.{ "libngtcp2_crypto_gnutls.so.2", "libngtcp2_crypto_gnutls.so", "/usr/lib/x86_64-linux-gnu/libngtcp2_crypto_gnutls.so.2" }) orelse return null;
    const L = std.DynLib;
    const loaded: NgApi = .{
        .lib = lib,
        .crypto_lib = crypto,
        .conn_client_new = lib.lookup(*const fn (*?*NgConn, *const NgCid, *const NgCid, *const NgPath, u32, c_int, *const NgCallbacks, c_int, *const anyopaque, c_int, *const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, "ngtcp2_conn_client_new_versioned") orelse return null,
        .conn_server_new = lib.lookup(*const fn (*?*NgConn, *const NgCid, *const NgCid, *const NgPath, u32, c_int, *const NgCallbacks, c_int, *const anyopaque, c_int, *const anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, "ngtcp2_conn_server_new_versioned") orelse return null,
        .conn_del = lib.lookup(*const fn (?*NgConn) callconv(.c) void, "ngtcp2_conn_del") orelse return null,
        .conn_read_pkt = lib.lookup(*const fn (?*NgConn, *const NgPath, c_int, *const NgPktInfo, [*]const u8, usize, u64) callconv(.c) c_int, "ngtcp2_conn_read_pkt_versioned") orelse return null,
        .conn_writev_stream = lib.lookup(*const fn (?*NgConn, ?*NgPath, c_int, ?*NgPktInfo, [*]u8, usize, ?*i64, u32, i64, ?[*]const NgVec, usize, u64) callconv(.c) i64, "ngtcp2_conn_writev_stream_versioned") orelse return null,
        .conn_write_connection_close = lib.lookup(*const fn (?*NgConn, ?*NgPath, c_int, ?*NgPktInfo, [*]u8, usize, *const NgCloseError, u64) callconv(.c) i64, "ngtcp2_conn_write_connection_close_versioned") orelse return null,
        .conn_open_bidi_stream = lib.lookup(*const fn (?*NgConn, *i64, ?*anyopaque) callconv(.c) c_int, "ngtcp2_conn_open_bidi_stream") orelse return null,
        .conn_open_uni_stream = lib.lookup(*const fn (?*NgConn, *i64, ?*anyopaque) callconv(.c) c_int, "ngtcp2_conn_open_uni_stream") orelse return null,
        .conn_get_expiry = lib.lookup(*const fn (?*NgConn) callconv(.c) u64, "ngtcp2_conn_get_expiry") orelse return null,
        .conn_handle_expiry = lib.lookup(*const fn (?*NgConn, u64) callconv(.c) c_int, "ngtcp2_conn_handle_expiry") orelse return null,
        .conn_set_tls_native_handle = lib.lookup(*const fn (?*NgConn, ?*anyopaque) callconv(.c) void, "ngtcp2_conn_set_tls_native_handle") orelse return null,
        .conn_extend_max_stream_offset = lib.lookup(*const fn (?*NgConn, i64, u64) callconv(.c) void, "ngtcp2_conn_extend_max_stream_offset") orelse return null,
        .conn_extend_max_offset = lib.lookup(*const fn (?*NgConn, u64) callconv(.c) void, "ngtcp2_conn_extend_max_offset") orelse return null,
        .conn_shutdown_stream_read = lib.lookup(*const fn (?*NgConn, i64, u64) callconv(.c) c_int, "ngtcp2_conn_shutdown_stream_read") orelse return null,
        .conn_shutdown_stream = lib.lookup(*const fn (?*NgConn, i64, u64) callconv(.c) c_int, "ngtcp2_conn_shutdown_stream") orelse return null,
        .accept = lib.lookup(*const fn (*NgPktHd, [*]const u8, usize) callconv(.c) c_int, "ngtcp2_accept") orelse return null,
        .settings_default = lib.lookup(*const fn (c_int, *anyopaque) callconv(.c) void, "ngtcp2_settings_default_versioned") orelse return null,
        .transport_params_default = lib.lookup(*const fn (c_int, *anyopaque) callconv(.c) void, "ngtcp2_transport_params_default_versioned") orelse return null,
        .crypto_configure_client = crypto.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ngtcp2_crypto_gnutls_configure_client_session") orelse return null,
        .crypto_configure_server = crypto.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ngtcp2_crypto_gnutls_configure_server_session") orelse return null,
        .cb_client_initial = crypto.lookup(*const anyopaque, "ngtcp2_crypto_client_initial_cb") orelse return null,
        .cb_recv_client_initial = crypto.lookup(*const anyopaque, "ngtcp2_crypto_recv_client_initial_cb") orelse return null,
        .cb_recv_crypto_data = crypto.lookup(*const anyopaque, "ngtcp2_crypto_recv_crypto_data_cb") orelse return null,
        .cb_recv_retry = crypto.lookup(*const anyopaque, "ngtcp2_crypto_recv_retry_cb") orelse return null,
        .cb_encrypt = crypto.lookup(*const anyopaque, "ngtcp2_crypto_encrypt_cb") orelse return null,
        .cb_decrypt = crypto.lookup(*const anyopaque, "ngtcp2_crypto_decrypt_cb") orelse return null,
        .cb_hp_mask = crypto.lookup(*const anyopaque, "ngtcp2_crypto_hp_mask_cb") orelse return null,
        .cb_update_key = crypto.lookup(*const anyopaque, "ngtcp2_crypto_update_key_cb") orelse return null,
        .cb_delete_aead_ctx = crypto.lookup(*const anyopaque, "ngtcp2_crypto_delete_crypto_aead_ctx_cb") orelse return null,
        .cb_delete_cipher_ctx = crypto.lookup(*const anyopaque, "ngtcp2_crypto_delete_crypto_cipher_ctx_cb") orelse return null,
        .cb_get_path_challenge_data = crypto.lookup(*const anyopaque, "ngtcp2_crypto_get_path_challenge_data_cb") orelse return null,
        .cb_version_negotiation = crypto.lookup(*const anyopaque, "ngtcp2_crypto_version_negotiation_cb") orelse return null,
    };
    _ = L;
    ng_api = loaded;
    return &ng_api.?;
}

fn loadGnuApi() ?*GnuApi {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    api_mutex.lockUncancelable(sio.io());
    defer api_mutex.unlock(sio.io());
    if (gnu_api) |*a| return a;
    var lib = openFirst(&.{ "libgnutls.so.30", "libgnutls.so", "/usr/lib/x86_64-linux-gnu/libgnutls.so.30" }) orelse return null;
    const loaded: GnuApi = .{
        .lib = lib,
        .init = lib.lookup(*const fn (*?*GnuSession, c_int) callconv(.c) c_int, "gnutls_init") orelse return null,
        .deinit = lib.lookup(*const fn (?*GnuSession) callconv(.c) void, "gnutls_deinit") orelse return null,
        .cert_allocate = lib.lookup(*const fn (*?*GnuCred) callconv(.c) c_int, "gnutls_certificate_allocate_credentials") orelse return null,
        .cert_free = lib.lookup(*const fn (?*GnuCred) callconv(.c) void, "gnutls_certificate_free_credentials") orelse return null,
        .cert_system_trust = lib.lookup(*const fn (?*GnuCred) callconv(.c) c_int, "gnutls_certificate_set_x509_system_trust") orelse return null,
        .cert_trust_file = lib.lookup(*const fn (?*GnuCred, [*:0]const u8, c_int) callconv(.c) c_int, "gnutls_certificate_set_x509_trust_file") orelse return null,
        .cert_key_file = lib.lookup(*const fn (?*GnuCred, [*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int, "gnutls_certificate_set_x509_key_file") orelse return null,
        .priority_set_direct = lib.lookup(*const fn (?*GnuSession, [*:0]const u8, ?*?*const u8) callconv(.c) c_int, "gnutls_priority_set_direct") orelse return null,
        .credentials_set = lib.lookup(*const fn (?*GnuSession, c_int, ?*GnuCred) callconv(.c) c_int, "gnutls_credentials_set") orelse return null,
        .alpn_set_protocols = lib.lookup(*const fn (?*GnuSession, [*]const GnuDatum, c_uint, c_uint) callconv(.c) c_int, "gnutls_alpn_set_protocols") orelse return null,
        .server_name_set = lib.lookup(*const fn (?*GnuSession, c_int, ?*const anyopaque, usize) callconv(.c) c_int, "gnutls_server_name_set") orelse return null,
        .session_set_ptr = lib.lookup(*const fn (?*GnuSession, ?*anyopaque) callconv(.c) void, "gnutls_session_set_ptr") orelse return null,
        .session_set_verify_cert = lib.lookup(*const fn (?*GnuSession, ?[*:0]const u8, c_uint) callconv(.c) void, "gnutls_session_set_verify_cert") orelse return null,
    };
    gnu_api = loaded;
    return &gnu_api.?;
}

fn loadH3Api() ?*H3Api {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    api_mutex.lockUncancelable(sio.io());
    defer api_mutex.unlock(sio.io());
    if (h3_api) |*a| return a;
    var lib = openFirst(&.{ "libnghttp3.so.3", "libnghttp3.so.9", "libnghttp3.so", "/usr/lib/x86_64-linux-gnu/libnghttp3.so.3" }) orelse return null;
    const loaded: H3Api = .{
        .lib = lib,
        .conn_client_new = lib.lookup(*const fn (*?*H3Conn, c_int, *const H3Callbacks, c_int, *const H3Settings, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, "nghttp3_conn_client_new_versioned") orelse return null,
        .conn_server_new = lib.lookup(*const fn (*?*H3Conn, c_int, *const H3Callbacks, c_int, *const H3Settings, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int, "nghttp3_conn_server_new_versioned") orelse return null,
        .conn_del = lib.lookup(*const fn (?*H3Conn) callconv(.c) void, "nghttp3_conn_del") orelse return null,
        .bind_control_stream = lib.lookup(*const fn (?*H3Conn, i64) callconv(.c) c_int, "nghttp3_conn_bind_control_stream") orelse return null,
        .bind_qpack_streams = lib.lookup(*const fn (?*H3Conn, i64, i64) callconv(.c) c_int, "nghttp3_conn_bind_qpack_streams") orelse return null,
        .read_stream = lib.lookup(*const fn (?*H3Conn, i64, [*]const u8, usize, c_int) callconv(.c) i64, "nghttp3_conn_read_stream") orelse return null,
        .writev_stream = lib.lookup(*const fn (?*H3Conn, ?*i64, ?*c_int, ?[*]H3Vec, usize) callconv(.c) i64, "nghttp3_conn_writev_stream") orelse return null,
        .add_write_offset = lib.lookup(*const fn (?*H3Conn, i64, usize) callconv(.c) c_int, "nghttp3_conn_add_write_offset") orelse return null,
        .add_ack_offset = lib.lookup(*const fn (?*H3Conn, i64, u64) callconv(.c) c_int, "nghttp3_conn_add_ack_offset") orelse return null,
        .submit_request = lib.lookup(*const fn (?*H3Conn, i64, [*]const H3Nv, usize, ?*const H3DataReader, ?*anyopaque) callconv(.c) c_int, "nghttp3_conn_submit_request") orelse return null,
        .submit_response = lib.lookup(*const fn (?*H3Conn, i64, [*]const H3Nv, usize, ?*const H3DataReader) callconv(.c) c_int, "nghttp3_conn_submit_response") orelse return null,
        .close_stream = lib.lookup(*const fn (?*H3Conn, i64, u64) callconv(.c) c_int, "nghttp3_conn_close_stream") orelse return null,
        .resume_stream = lib.lookup(*const fn (?*H3Conn, i64) callconv(.c) c_int, "nghttp3_conn_resume_stream") orelse return null,
        .block_stream = lib.lookup(*const fn (?*H3Conn, i64) callconv(.c) c_int, "nghttp3_conn_block_stream") orelse return null,
        .set_stream_user_data = lib.lookup(*const fn (?*H3Conn, i64, ?*anyopaque) callconv(.c) c_int, "nghttp3_conn_set_stream_user_data") orelse return null,
        .rcbuf_get_buf = lib.lookup(*const fn (?*const H3Rcbuf) callconv(.c) H3Vec, "nghttp3_rcbuf_get_buf") orelse return null,
    };
    h3_api = loaded;
    return &h3_api.?;
}

fn quicStackAvailable() bool {
    return loadNgApi() != null and loadGnuApi() != null and loadH3Api() != null;
}

// ---- connection objects -------------------------------------------------------

const SockStorage = std.posix.sockaddr.storage;

const RawStream = struct {
    recv: std.ArrayListUnmanaged(u8) = .empty,
    recv_off: usize = 0,
    recv_fin: bool = false,
    closed: bool = false,
    send: std.ArrayListUnmanaged(u8) = .empty,
    send_off: usize = 0,
    send_fin: bool = false,
    send_done: bool = false,
    fin_in_pending: bool = false,
};

const QuicConn = struct {
    conn: ?*NgConn = null,
    session: ?*GnuSession = null,
    cred: ?*GnuCred = null, // client-owned only; server conns share the listener cred (null here)
    conn_ref: NgCryptoConnRef = undefined,
    fd: std.posix.fd_t,
    owns_fd: bool,
    is_server: bool,
    local: SockStorage = undefined,
    local_len: std.posix.socklen_t = 0,
    peer: SockStorage = undefined,
    peer_len: std.posix.socklen_t = 0,
    scid: [8]u8 = @splat(0),
    sni_z: ?[:0]u8 = null, // owned; gnutls keeps the verify hostname pointer
    handshake_done: bool = false,
    closed: bool = false,
    streams: std.AutoHashMapUnmanaged(i64, *RawStream) = .empty,
    h3: ?*H3Session = null,
    listener: ?*QuicListener = null,

    fn path(self: *QuicConn) NgPath {
        return .{
            .local = .{ .addr = @ptrCast(&self.local), .addrlen = self.local_len },
            .remote = .{ .addr = @ptrCast(&self.peer), .addrlen = self.peer_len },
            .user_data = null,
        };
    }
    fn sendPacket(self: *QuicConn, bytes: []const u8) void {
        if (self.owns_fd) {
            _ = std.os.linux.sendto(self.fd, bytes.ptr, bytes.len, 0, null, 0);
        } else {
            _ = std.os.linux.sendto(self.fd, bytes.ptr, bytes.len, 0, @ptrCast(&self.peer), self.peer_len);
        }
    }
    fn getStream(self: *QuicConn, id: i64) ?*RawStream {
        return self.streams.get(id);
    }
    fn ensureStream(self: *QuicConn, id: i64) !*RawStream {
        if (self.streams.get(id)) |s| return s;
        const s = try std.heap.page_allocator.create(RawStream);
        s.* = .{};
        try self.streams.put(std.heap.page_allocator, id, s);
        return s;
    }
};

const QuicListener = struct {
    fd: std.posix.fd_t,
    cred: ?*GnuCred = null,
    local: SockStorage = undefined,
    local_len: std.posix.socklen_t = 0,
    pending: std.ArrayListUnmanaged(*QuicConn) = .empty,
    conns: std.ArrayListUnmanaged(*QuicConn) = .empty,
    route: std.AutoHashMapUnmanaged(u64, *QuicConn) = .empty,
};

const QuicEndpoint = struct {
    listener: ?*QuicListener = null,
};

// ---- ngtcp2 callbacks ----------------------------------------------------------

fn cryptoGetConn(ref: ?*NgCryptoConnRef) callconv(.c) ?*NgConn {
    const r = ref orelse return null;
    const qc: *QuicConn = @ptrCast(@alignCast(r.user_data orelse return null));
    return qc.conn;
}

fn cbRand(dest: [*]u8, destlen: usize, ctx: ?*const anyopaque) callconv(.c) void {
    _ = ctx;
    sio.io().random(dest[0..destlen]);
}

fn cbGetNewConnectionId(conn: ?*NgConn, cid: ?*NgCid, token: [*]u8, cidlen: usize, user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = user_data;
    const c = cid orelse return -1;
    if (cidlen > NG_MAX_CIDLEN) return -1;
    sio.io().random(c.data[0..cidlen]);
    c.datalen = cidlen;
    sio.io().random(token[0..16]);
    return 0;
}

fn cbHandshakeCompleted(conn: ?*NgConn, user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    qc.handshake_done = true;
    return 0;
}

fn cbRecvStreamData(conn: ?*NgConn, flags: u32, stream_id: i64, offset: u64, data: [*]const u8, datalen: usize, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
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

fn cbAckedStreamData(conn: ?*NgConn, stream_id: i64, offset: u64, datalen: u64, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = offset;
    _ = stream_user_data;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    if (qc.h3) |sess| return sess.ackedStreamData(stream_id, datalen);
    return 0;
}

fn cbStreamClose(conn: ?*NgConn, flags: u32, stream_id: i64, app_error_code: u64, user_data: ?*anyopaque, stream_user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = flags;
    _ = stream_user_data;
    const qc: *QuicConn = @ptrCast(@alignCast(user_data orelse return 0));
    if (qc.getStream(stream_id)) |s| s.closed = true;
    if (qc.h3) |sess| return sess.streamClosed(stream_id, app_error_code);
    return 0;
}

fn makeCallbacks(ng: *NgApi, qc: *QuicConn) NgCallbacks {
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

fn writeTpField(tp: []u8, off: usize, v: u64) void {
    std.mem.writeInt(u64, tp[off..][0..8], v, .little);
}

fn buildSettings(ng: *NgApi, ts: u64) [NG_SETTINGS_SIZE]u8 {
    var b: [NG_SETTINGS_SIZE]u8 = @splat(0);
    ng.settings_default(1, &b);
    std.mem.writeInt(u64, b[NG_SETTINGS_OFF_INITIAL_TS..][0..8], ts, .little);
    return b;
}

fn buildTransportParams(ng: *NgApi, original_dcid: ?NgCid) [NG_TP_SIZE]u8 {
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
        std.mem.writeInt(usize, b[NG_TP_OFF_ORIGINAL_DCID..][0..8], cid.datalen, .little);
        @memcpy(b[NG_TP_OFF_ORIGINAL_DCID + 8 ..][0..20], &cid.data);
    }
    return b;
}

// ---- UDP + address helpers ------------------------------------------------------

fn parseIp4Literal(host: []const u8, port: u16) ?std.posix.sockaddr.in {
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

fn resolveIp4(host: []const u8, port: u16) !std.posix.sockaddr.in {
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

fn storageFromIn(sa: std.posix.sockaddr.in) struct { storage: SockStorage, len: std.posix.socklen_t } {
    var storage: SockStorage = undefined;
    @memcpy(std.mem.asBytes(&storage)[0..@sizeOf(std.posix.sockaddr.in)], std.mem.asBytes(&sa));
    return .{ .storage = storage, .len = @sizeOf(std.posix.sockaddr.in) };
}

fn udpSocket() !std.posix.fd_t {
    const rc = std.os.linux.socket(std.posix.AF.INET, std.os.linux.SOCK.DGRAM | std.os.linux.SOCK.CLOEXEC | std.os.linux.SOCK.NONBLOCK, 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.SocketFailed;
    return @intCast(rc);
}

fn socketLocalAddr(fd: std.posix.fd_t, out: *SockStorage, out_len: *std.posix.socklen_t) !void {
    out_len.* = @sizeOf(SockStorage);
    const rc = std.os.linux.getsockname(fd, @ptrCast(out), out_len);
    if (@as(isize, @bitCast(rc)) < 0) return error.GetsocknameFailed;
}

// ---- GnuTLS session setup --------------------------------------------------------

const GNUTLS_ALPN_H3 = "h3";

fn gnuSetAlpn(ga: *GnuApi, session: *GnuSession, alpn: []const u8) !void {
    var datums = [1]GnuDatum{.{ .data = @constCast(alpn.ptr), .size = @intCast(alpn.len) }};
    if (ga.alpn_set_protocols(session, &datums, 1, GNUTLS_ALPN_MANDATORY) != 0) return error.AlpnFailed;
}

fn gnuClientSession(ga: *GnuApi, ng: *NgApi, qc: *QuicConn, server_name: []const u8, ca_file: ?[]const u8, alpn: []const u8) !void {
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

fn gnuServerSession(ga: *GnuApi, ng: *NgApi, qc: *QuicConn, shared_cred: *GnuCred, alpn: []const u8) !void {
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

const PKT_BUF = 1452;
const H3_WRITE_BLOCKED: i64 = -2_000_000_002;

fn flushWrites(qc: *QuicConn) void {
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

fn strArg(ptr_: ?[*]const u8, len: u64) ?[]const u8 {
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

fn endpointFrom(handle: u64) ?*QuicEndpoint {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn connFrom(handle: u64) ?*QuicConn {
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
    errdefer _ = std.os.linux.close(fd);
    const peer_st = storageFromIn(addr);
    if (@as(isize, @bitCast(std.os.linux.connect(fd, @ptrCast(&peer_st.storage), peer_st.len))) < 0) return SA_STD_ERR_IO;

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
        _ = std.os.linux.close(fd);
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
    errdefer _ = std.os.linux.close(fd);
    const bind_addr = parseIp4Literal("0.0.0.0", @intCast(port)).?;
    const bs = storageFromIn(bind_addr);
    if (@as(isize, @bitCast(std.os.linux.bind(fd, @ptrCast(&bs.storage), bs.len))) < 0) return SA_STD_ERR_IO;

    const l = std.heap.page_allocator.create(QuicListener) catch return SA_STD_ERR_NO_MEMORY;
    l.* = .{ .fd = fd, .cred = cred };
    socketLocalAddr(fd, &l.local, &l.local_len) catch {
        std.heap.page_allocator.destroy(l);
        return SA_STD_ERR_IO;
    };
    ep.listener = l;
    return SA_STD_OK;
}

fn destroyListener(l: *QuicListener) void {
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
    _ = std.os.linux.close(l.fd);
    std.heap.page_allocator.destroy(l);
}

fn destroyConn(qc: *QuicConn, send_close: bool) void {
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
    if (qc.owns_fd) _ = std.os.linux.close(qc.fd);
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

// ---- server accept machinery ---------------------------------------------------------

fn createServerConn(l: *QuicListener, hd: *const NgPktHd, src: *const SockStorage, src_len: std.posix.socklen_t) ?*QuicConn {
    const ng = loadNgApi() orelse return null;
    const ga = loadGnuApi() orelse return null;
    const qc = std.heap.page_allocator.create(QuicConn) catch return null;
    qc.* = .{ .fd = l.fd, .owns_fd = false, .is_server = true, .listener = l };
    qc.local = l.local;
    qc.local_len = l.local_len;
    qc.peer = src.*;
    qc.peer_len = src_len;
    qc.conn_ref = .{ .get_conn = &cryptoGetConn, .user_data = qc };
    gnuServerSession(ga, ng, qc, l.cred.?, GNUTLS_ALPN_H3) catch {
        std.heap.page_allocator.destroy(qc);
        return null;
    };
    var scid: NgCid = .{ .datalen = 8, .data = @splat(0) };
    sio.io().random(scid.data[0..8]);
    @memcpy(&qc.scid, scid.data[0..8]);
    const cbs = makeCallbacks(ng, qc);
    const settings = buildSettings(ng, nowNs());
    const tp = buildTransportParams(ng, hd.dcid);
    var p = qc.path();
    var conn: ?*NgConn = null;
    if (ng.conn_server_new(&conn, &hd.scid, &scid, &p, hd.version, 1, &cbs, 1, &settings, 1, &tp, null, qc) != 0) {
        if (qc.session) |sess| ga.deinit(sess);
        std.heap.page_allocator.destroy(qc);
        return null;
    }
    qc.conn = conn;
    ng.conn_set_tls_native_handle(conn, qc.session);
    l.conns.append(std.heap.page_allocator, qc) catch return null;
    l.pending.append(std.heap.page_allocator, qc) catch return null;
    const key = std.mem.readInt(u64, &qc.scid, .big);
    l.route.put(std.heap.page_allocator, key, qc) catch return null;
    return qc;
}

fn dispatchDatagram(l: *QuicListener, bytes: []const u8, src: *const SockStorage, src_len: std.posix.socklen_t) void {
    const ng = loadNgApi() orelse return;
    if (bytes.len == 0) return;
    var target: ?*QuicConn = null;
    if ((bytes[0] & 0x80) != 0) {
        var hd = NgPktHd{ .dcid = .{ .datalen = 0, .data = @splat(0) }, .scid = .{ .datalen = 0, .data = @splat(0) }, .token = .{ .base = null, .len = 0 }, .version = 0, .type_ = 0 };
        if (ng.accept(&hd, bytes.ptr, bytes.len) != 0) return;
        if (hd.version == 0) return;
        if (hd.dcid.datalen == 8) {
            const key = std.mem.readInt(u64, hd.dcid.data[0..8], .big);
            if (l.route.get(key)) |c| target = c;
        }
        if (target == null) {
            if ((bytes[0] & 0x30) != 0) return; // not an Initial
            target = createServerConn(l, &hd, src, src_len);
        }
    } else {
        if (bytes.len < 9) return;
        const key = std.mem.readInt(u64, bytes[1..9], .big);
        target = l.route.get(key);
    }
    const qc = target orelse return;
    {
        var it = qc.streams.valueIterator();
        while (it.next()) |sp| {
            if (sp.*.fin_in_pending) {
                flushWrites(qc);
                break;
            }
        }
    }
    qc.peer = src.*;
    qc.peer_len = src_len;
    var p = qc.path();
    var pi = NgPktInfo{ .ecn = 0 };
    _ = ng.conn_read_pkt(qc.conn, &p, 1, &pi, bytes.ptr, bytes.len, nowNs());
}

fn driveConnTimersAndFlush(qc: *QuicConn) void {
    const ng = loadNgApi() orelse return;
    if (qc.conn) |conn| {
        const now = nowNs();
        if (ng.conn_get_expiry(conn) <= now) {
            _ = ng.conn_handle_expiry(conn, now);
        }
    }
    if (qc.h3) |sess| sess.maybeBind();
    flushWrites(qc);
}

pub export fn sa_std_quic_server_poll(endpoint: u64, timeout_ms: u32) i32 {
    const ep = endpointFrom(endpoint) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const l = ep.listener orelse return SA_STD_ERR_INVALID_ARGUMENT;
    var fds = [_]std.posix.pollfd{.{ .fd = l.fd, .events = std.posix.POLL.IN, .revents = 0 }};
    _ = std.posix.poll(&fds, @intCast(timeout_ms)) catch return SA_STD_ERR_IO;
    var buf: [65536]u8 = undefined;
    var guard_n: usize = 0;
    while (guard_n < 256) : (guard_n += 1) {
        var src: SockStorage = undefined;
        var src_len: std.posix.socklen_t = @sizeOf(SockStorage);
        const rc = std.os.linux.recvfrom(l.fd, &buf, buf.len, 0, @ptrCast(&src), &src_len);
        if (@as(isize, @bitCast(rc)) <= 0) break;
        const n = rc;
        dispatchDatagram(l, buf[0..n], &src, src_len);
    }
    for (l.conns.items) |qc| driveConnTimersAndFlush(qc);
    return SA_STD_OK;
}

pub export fn sa_std_quic_server_accept(endpoint: u64, out_conn: ?*u64) i32 {
    const slot = out_conn orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const ep = endpointFrom(endpoint) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const l = ep.listener orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (l.pending.items.len == 0) return SA_STD_ERR_AGAIN;
    const qc = l.pending.orderedRemove(0);
    slot.* = @intFromPtr(qc);
    return SA_STD_OK;
}

pub export fn sa_std_quic_conn_poll(handle: u64, timeout_ms: u32) i32 {
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    if (qc.is_server) {
        // Incoming data for server conns is drained by server_poll (the
        // listener owns the socket); here we only run timers + flush.
        driveConnTimersAndFlush(qc);
        return SA_STD_OK;
    }
    flushWrites(qc);
    var wait_ms: i32 = @intCast(timeout_ms);
    if (qc.conn) |conn| {
        const now = nowNs();
        const expiry = ng.conn_get_expiry(conn);
        if (expiry > now) {
            const until = @as(i64, @intCast((expiry - now) / 1_000_000));
            if (until < wait_ms) wait_ms = @intCast(@max(until, 0));
        } else {
            wait_ms = 0;
        }
    }
    var fds = [_]std.posix.pollfd{.{ .fd = qc.fd, .events = std.posix.POLL.IN, .revents = 0 }};
    _ = std.posix.poll(&fds, wait_ms) catch return SA_STD_ERR_IO;
    var buf: [65536]u8 = undefined;
    var guard_n: usize = 0;
    while (guard_n < 256) : (guard_n += 1) {
        const rc = std.os.linux.recvfrom(qc.fd, &buf, buf.len, 0, null, null);
        if (@as(isize, @bitCast(rc)) <= 0) break;
        const n = rc;
        var p = qc.path();
        var pi = NgPktInfo{ .ecn = 0 };
        _ = ng.conn_read_pkt(qc.conn, &p, 1, &pi, &buf, n, nowNs());
    }
    driveConnTimersAndFlush(qc);
    return SA_STD_OK;
}

// ---- raw stream surface --------------------------------------------------------------

pub export fn sa_std_quic_stream_open(handle: u64, out_stream_id: ?*i64) i32 {
    const slot = out_stream_id orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = -1;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ng = loadNgApi() orelse return SA_STD_ERR_UNSUPPORTED;
    var sid: i64 = -1;
    if (ng.conn_open_bidi_stream(qc.conn, &sid, null) != 0) return SA_STD_ERR_IO;
    _ = qc.ensureStream(sid) catch return SA_STD_ERR_NO_MEMORY;
    slot.* = sid;
    return SA_STD_OK;
}

pub export fn sa_std_quic_stream_write(handle: u64, stream_id: i64, data_ptr: ?[*]const u8, data_len: u64, fin: u32, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = u64ToUsize(data_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const data = if (data_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const s = qc.ensureStream(stream_id) catch return SA_STD_ERR_NO_MEMORY;
    s.send.appendSlice(std.heap.page_allocator, data) catch return SA_STD_ERR_NO_MEMORY;
    if (fin != 0) s.send_fin = true;
    slot.* = data_len;
    return SA_STD_OK;
}

pub export fn sa_std_quic_stream_read(handle: u64, stream_id: i64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_fin: ?*u32) i32 {
    const rslot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    rslot.* = 0;
    if (out_fin) |f| f.* = 0;
    const qc = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = qc.getStream(stream_id) orelse return SA_STD_ERR_AGAIN;
    const avail = s.recv.items.len - s.recv_off;
    const n = @min(avail, u64ToUsize(cap) orelse return SA_STD_ERR_INVALID_ARGUMENT);
    if (n > 0) {
        const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
        @memcpy(buf[0..n], s.recv.items[s.recv_off..][0..n]);
        s.recv_off += n;
        rslot.* = @intCast(n);
    }
    if (s.recv_off >= s.recv.items.len) {
        s.recv.clearRetainingCapacity();
        s.recv_off = 0;
    }
    if (out_fin) |f| f.* = if (s.recv_fin and s.recv_off >= s.recv.items.len) 1 else 0;
    if (n == 0 and !s.recv_fin) return SA_STD_ERR_AGAIN;
    return SA_STD_OK;
}

// ---- HTTP/3 session --------------------------------------------------------------------

const H3Header = struct { name: []u8, value: []u8 };

const H3StreamState = struct {
    headers: std.ArrayListUnmanaged(H3Header) = .empty,
    status: u32 = 0,
    body: std.ArrayListUnmanaged(u8) = .empty,
    body_off: usize = 0,
    body_fin: bool = false,
    closed: bool = false,
    send_body: []u8 = &.{},
    send_off: usize = 0,
    pending_in: std.ArrayListUnmanaged(u8) = .empty,
    pending_in_fin: bool = false,

    fn header(self: *const H3StreamState, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.mem.eql(u8, h.name, name)) return h.value;
        }
        return null;
    }
};

const H3Session = struct {
    h3: ?*H3Conn = null,
    qc: ?*QuicConn = null,
    is_server: bool = false,
    bound: bool = false,
    streams: std.AutoHashMapUnmanaged(i64, *H3StreamState) = .empty,
    pending_requests: std.ArrayListUnmanaged(i64) = .empty,
    last_error: i64 = 0,

    fn ensureStream(self: *H3Session, id: i64) !*H3StreamState {
        if (self.streams.get(id)) |s| return s;
        const s = try std.heap.page_allocator.create(H3StreamState);
        s.* = .{};
        try self.streams.put(std.heap.page_allocator, id, s);
        return s;
    }
    fn getStream(self: *H3Session, id: i64) ?*H3StreamState {
        return self.streams.get(id);
    }

    fn maybeBind(self: *H3Session) void {
        if (self.bound) return;
        const qc = self.qc orelse return;
        if (!qc.handshake_done) return;
        const ng = loadNgApi() orelse return;
        const ha = loadH3Api() orelse return;
        const h3 = self.h3 orelse return;
        var ctrl: i64 = -1;
        var enc: i64 = -1;
        var dec: i64 = -1;
        if (ng.conn_open_uni_stream(qc.conn, &ctrl, null) != 0) return;
        if (ng.conn_open_uni_stream(qc.conn, &enc, null) != 0) return;
        if (ng.conn_open_uni_stream(qc.conn, &dec, null) != 0) return;
        if (ha.bind_control_stream(h3, ctrl) != 0) return;
        if (ha.bind_qpack_streams(h3, enc, dec) != 0) return;
        self.bound = true;
    }

    fn feedStreamData(self: *H3Session, stream_id: i64, bytes: []const u8, fin: bool) c_int {
        const ha = loadH3Api() orelse return -1;
        const ng = loadNgApi() orelse return -1;
        const qc = self.qc orelse return -1;
        const h3 = self.h3 orelse return -1;
        const st = self.ensureStream(stream_id) catch return -1;
        var input = bytes;
        var input_fin = fin;
        if (st.pending_in.items.len > 0) {
            // Earlier bytes were not fully consumed; they go first.
            st.pending_in.appendSlice(std.heap.page_allocator, bytes) catch return -1;
            if (fin) st.pending_in_fin = true;
            input = st.pending_in.items;
            input_fin = st.pending_in_fin;
        }
        const consumed = ha.read_stream(h3, stream_id, input.ptr, input.len, if (input_fin) 1 else 0);
        if (consumed < 0) {
            self.last_error = consumed;
            return 0;
        }
        const used: usize = @intCast(consumed);
        if (used > 0) {
            ng.conn_extend_max_stream_offset(qc.conn, stream_id, used);
            ng.conn_extend_max_offset(qc.conn, used);
        }
        if (used < input.len) {
            if (st.pending_in.items.len == 0) {
                st.pending_in.appendSlice(std.heap.page_allocator, input[used..]) catch return -1;
                st.pending_in_fin = input_fin;
            } else {
                const rest = st.pending_in.items[used..];
                std.mem.copyForwards(u8, st.pending_in.items, rest);
                st.pending_in.shrinkRetainingCapacity(rest.len);
            }
        } else {
            st.pending_in.clearRetainingCapacity();
            st.pending_in_fin = false;
        }
        return 0;
    }

    fn retryPending(self: *H3Session) void {
        var it = self.streams.iterator();
        while (it.next()) |e| {
            const st = e.value_ptr.*;
            if (st.pending_in.items.len > 0) {
                _ = self.feedStreamData(e.key_ptr.*, &.{}, false);
            }
        }
    }

    fn ackedStreamData(self: *H3Session, stream_id: i64, datalen: u64) c_int {
        const ha = loadH3Api() orelse return -1;
        const h3 = self.h3 orelse return -1;
        _ = ha.add_ack_offset(h3, stream_id, datalen);
        return 0;
    }

    fn streamClosed(self: *H3Session, stream_id: i64, app_error_code: u64) c_int {
        const ha = loadH3Api() orelse return -1;
        if (self.getStream(stream_id)) |st| st.closed = true;
        const h3 = self.h3 orelse return -1;
        _ = ha.close_stream(h3, stream_id, app_error_code);
        return 0;
    }

    fn writeStep(self: *H3Session, path: *NgPath, pi: *NgPktInfo, buf: []u8, wdatalen_out: *i64) i64 {
        const ng = loadNgApi() orelse return -1;
        const ha = loadH3Api() orelse return -1;
        const qc = self.qc orelse return -1;
        const h3 = self.h3 orelse return -1;
        self.retryPending();
        var iter: usize = 0;
        while (iter < 64) : (iter += 1) {
            var sid: i64 = -1;
            var fin: c_int = 0;
            var vecs: [4]H3Vec = undefined;
            const nvec = ha.writev_stream(h3, &sid, &fin, &vecs, 4);
            if (nvec < 0) {
                self.last_error = nvec;
                return H3_WRITE_BLOCKED;
            }
            if (nvec == 0) return H3_WRITE_BLOCKED;
            var ngvecs: [4]NgVec = undefined;
            for (0..@intCast(nvec)) |i| {
                ngvecs[i] = .{ .base = vecs[i].base, .len = vecs[i].len };
            }
            var flags: u32 = NG_WRITE_STREAM_FLAG_MORE;
            if (fin == 1) flags |= NG_WRITE_STREAM_FLAG_FIN;
            var wdatalen: i64 = 0;
            const nw = ng.conn_writev_stream(qc.conn, path, 1, pi, buf.ptr, buf.len, &wdatalen, flags, sid, &ngvecs, @intCast(nvec), nowNs());
            if (nw == NG_ERR_WRITE_MORE) {
                if (wdatalen > 0) _ = ha.add_write_offset(h3, sid, @intCast(wdatalen));
                continue;
            }
            if (nw < 0) return nw;
            if (wdatalen > 0) _ = ha.add_write_offset(h3, sid, @intCast(wdatalen));
            if (nw == 0) return H3_WRITE_BLOCKED;
            wdatalen_out.* = wdatalen;
            return nw;
        }
        return H3_WRITE_BLOCKED;
    }

    fn destroy(self: *H3Session) void {
        const ha = loadH3Api();
        if (self.h3) |h| {
            if (ha) |a| a.conn_del(h);
        }
        var it = self.streams.valueIterator();
        while (it.next()) |sp| {
            const st = sp.*;
            for (st.headers.items) |hd| {
                std.heap.page_allocator.free(hd.name);
                std.heap.page_allocator.free(hd.value);
            }
            st.headers.deinit(std.heap.page_allocator);
            st.body.deinit(std.heap.page_allocator);
            st.pending_in.deinit(std.heap.page_allocator);
            if (st.send_body.len > 0) std.heap.page_allocator.free(st.send_body);
            std.heap.page_allocator.destroy(st);
        }
        self.streams.deinit(std.heap.page_allocator);
        self.pending_requests.deinit(std.heap.page_allocator);
        std.heap.page_allocator.destroy(self);
    }
};

// nghttp3 callbacks
fn h3cbAcked(conn: ?*H3Conn, stream_id: i64, datalen: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_id;
    _ = datalen;
    _ = conn_ud;
    _ = stream_ud;
    return 0;
}
fn h3cbStreamClose(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = app_error_code;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    if (sess.getStream(stream_id)) |st| st.closed = true;
    return 0;
}
fn h3cbRecvData(conn: ?*H3Conn, stream_id: i64, data: [*]const u8, datalen: usize, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const st = sess.ensureStream(stream_id) catch return -1;
    st.body.appendSlice(std.heap.page_allocator, data[0..datalen]) catch return -1;
    return 0;
}
fn h3cbBeginHeaders(conn: ?*H3Conn, stream_id: i64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    _ = sess.ensureStream(stream_id) catch return -1;
    return 0;
}
fn h3cbRecvHeader(conn: ?*H3Conn, stream_id: i64, token: i32, name: ?*H3Rcbuf, value: ?*H3Rcbuf, flags: u8, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = token;
    _ = flags;
    _ = stream_ud;
    const ha = loadH3Api() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const st = sess.ensureStream(stream_id) catch return -1;
    const nb = ha.rcbuf_get_buf(name);
    const vb = ha.rcbuf_get_buf(value);
    const nname = std.heap.page_allocator.dupe(u8, (nb.base orelse return -1)[0..nb.len]) catch return -1;
    errdefer std.heap.page_allocator.free(nname);
    const nvalue = std.heap.page_allocator.dupe(u8, (vb.base orelse return -1)[0..vb.len]) catch return -1;
    errdefer std.heap.page_allocator.free(nvalue);
    st.headers.append(std.heap.page_allocator, .{ .name = nname, .value = nvalue }) catch return -1;
    if (std.mem.eql(u8, nname, ":status")) {
        st.status = std.fmt.parseInt(u32, nvalue, 10) catch 0;
    }
    return 0;
}
fn h3cbEndHeaders(conn: ?*H3Conn, stream_id: i64, fin: c_int, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = fin;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    _ = sess.ensureStream(stream_id) catch return -1;
    if (sess.is_server) {
        sess.pending_requests.append(std.heap.page_allocator, stream_id) catch return -1;
    }
    return 0;
}
fn h3cbEndStream(conn: ?*H3Conn, stream_id: i64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    if (sess.getStream(stream_id)) |st| st.body_fin = true;
    return 0;
}
fn h3cbStopSending(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const ng = loadNgApi() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const qc = sess.qc orelse return -1;
    _ = ng.conn_shutdown_stream_read(qc.conn, stream_id, app_error_code);
    return 0;
}
fn h3cbResetStream(conn: ?*H3Conn, stream_id: i64, app_error_code: u64, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = stream_ud;
    const ng = loadNgApi() orelse return -1;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return 0));
    const qc = sess.qc orelse return -1;
    _ = ng.conn_shutdown_stream(qc.conn, stream_id, app_error_code);
    return 0;
}
fn h3ReadData(conn: ?*H3Conn, stream_id: i64, vecs: [*]H3Vec, veccnt: usize, pflags: *u32, conn_ud: ?*anyopaque, stream_ud: ?*anyopaque) callconv(.c) i64 {
    _ = conn;
    _ = stream_ud;
    const sess: *H3Session = @ptrCast(@alignCast(conn_ud orelse return -1));
    const st = sess.getStream(stream_id) orelse {
        pflags.* = H3_DATA_FLAG_EOF;
        return 0;
    };
    if (veccnt == 0) return 0;
    const remaining = st.send_body.len - st.send_off;
    if (remaining == 0) {
        pflags.* = H3_DATA_FLAG_EOF;
        return 0;
    }
    vecs[0] = .{ .base = st.send_body.ptr + st.send_off, .len = remaining };
    st.send_off += remaining;
    return 1;
}

fn makeH3Callbacks() H3Callbacks {
    var cbs = H3Callbacks{ .fields = @splat(null) };
    cbs.fields[H3CB_ACKED_STREAM_DATA] = @ptrCast(&h3cbAcked);
    cbs.fields[H3CB_STREAM_CLOSE] = @ptrCast(&h3cbStreamClose);
    cbs.fields[H3CB_RECV_DATA] = @ptrCast(&h3cbRecvData);
    cbs.fields[H3CB_BEGIN_HEADERS] = @ptrCast(&h3cbBeginHeaders);
    cbs.fields[H3CB_RECV_HEADER] = @ptrCast(&h3cbRecvHeader);
    cbs.fields[H3CB_END_HEADERS] = @ptrCast(&h3cbEndHeaders);
    cbs.fields[H3CB_STOP_SENDING] = @ptrCast(&h3cbStopSending);
    cbs.fields[H3CB_END_STREAM] = @ptrCast(&h3cbEndStream);
    cbs.fields[H3CB_RESET_STREAM] = @ptrCast(&h3cbResetStream);
    return cbs;
}

pub export fn sa_std_http3_session_create(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (!quicStackAvailable()) return SA_STD_ERR_UNSUPPORTED;
    const sess = std.heap.page_allocator.create(H3Session) catch return SA_STD_ERR_NO_MEMORY;
    sess.* = .{};
    slot.* = @intFromPtr(sess);
    return SA_STD_OK;
}

fn sessionFrom(handle: u64) ?*H3Session {
    if (handle == 0) return null;
    const p: *H3Session = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_http3_session_bind(session: u64, quic_conn: u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const qc = connFrom(quic_conn) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ha = loadH3Api() orelse return SA_STD_ERR_UNSUPPORTED;
    if (sess.h3 != null or qc.h3 != null) return SA_STD_ERR_INVALID_ARGUMENT;
    sess.qc = qc;
    sess.is_server = qc.is_server;
    const cbs = makeH3Callbacks();
    const settings = H3Settings{ .max_field_section_size = 0, .qpack_max_dtable_capacity = 4096, .qpack_encoder_max_dtable_capacity = 4096, .qpack_blocked_streams = 100, .enable_connect_protocol = 0 };
    var h3: ?*H3Conn = null;
    const rc = if (qc.is_server)
        ha.conn_server_new(&h3, 1, &cbs, 1, &settings, null, sess)
    else
        ha.conn_client_new(&h3, 1, &cbs, 1, &settings, null, sess);
    if (rc != 0) {
        sess.qc = null;
        return SA_STD_ERR_IO;
    }
    sess.h3 = h3;
    qc.h3 = sess;
    sess.maybeBind();
    return SA_STD_OK;
}

pub export fn sa_std_http3_session_destroy(session: u64) i32 {
    const sess = sessionFrom(session) orelse return SA_STD_OK;
    if (sess.qc) |qc| {
        if (qc.h3 == sess) qc.h3 = null;
    }
    sess.destroy();
    return SA_STD_OK;
}

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

const SA_STD_ERR_TRUNCATED: i32 = 9;

fn writeStringOut(out: ?[*]u8, out_cap: u64, out_len: ?*u64, bytes: []const u8) i32 {
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
var string_mutex = std.Io.Mutex.init;
var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

fn registerString(bytes: []u8, slot: *u64) i32 {
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
fn takeString(handle: u64) ?[]u8 {
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

fn registerOwned(text: []const u8, slot: *u64) i32 {
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

const testing = std.testing;

fn stackAvailable() bool {
    var flag: u32 = 0;
    if (sa_std_quic_supported(&flag) != SA_STD_OK) return false;
    return flag == 1;
}

// On hosts where the stack MUST be present (the dev/CI box), set
// SCI_REQUIRE_QUIC=1 so a missing library fails loudly instead of
// silently skipping the loopback tests.
fn stackOrSkip() !bool {
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

fn makeCertPair(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
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

fn freeUdpPort() !u16 {
    const fd = try udpSocket();
    defer _ = std.os.linux.close(fd);
    const addr = parseIp4Literal("127.0.0.1", 0).?;
    const bs = storageFromIn(addr);
    if (@as(isize, @bitCast(std.os.linux.bind(fd, @ptrCast(&bs.storage), bs.len))) < 0) return error.BindFailed;
    var storage: SockStorage = undefined;
    var len: std.posix.socklen_t = @sizeOf(SockStorage);
    try socketLocalAddr(fd, &storage, &len);
    const sa: *const std.posix.sockaddr.in = @ptrCast(@alignCast(&storage));
    return std.mem.bigToNative(u16, sa.port);
}

const Loopback = struct {
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

fn setupLoopback(allocator: std.mem.Allocator, td: *testing.TmpDir) !Loopback {
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
