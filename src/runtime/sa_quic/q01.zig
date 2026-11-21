const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const H3Session = @import("q03.zig").H3Session;
const lxSendTo = @import("q02.zig").lxSendTo;

pub const SA_STD_OK: i32 = 0;

pub const SA_STD_ERR_UNSUPPORTED: i32 = -1;

pub const SA_STD_ERR_IO: i32 = -5;

pub const SA_STD_ERR_AGAIN: i32 = -11;

pub const SA_STD_ERR_NO_MEMORY: i32 = -12;

pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;

pub fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub fn nowNs() u64 {
    const v = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (v <= 0) return 0;
    return @intCast(@min(v, @as(i96, std.math.maxInt(u64))));
}

pub fn toZ(alloc: std.mem.Allocator, text: []const u8) ?[:0]u8 {
    const z = alloc.allocSentinel(u8, text.len, 0) catch return null;
    @memcpy(z, text);
    return z;
}

// ---- ngtcp2 ABI (verified against ngtcp2 0.12.1 headers) -------------------
pub const NgConn = opaque {};

pub const NgCid = extern struct {
    datalen: usize,
    data: [20]u8,
};

pub const NgVec = extern struct {
    base: ?[*]u8,
    len: usize,
};

pub const NgSockaddr = std.posix.sockaddr;

pub const NgAddr = extern struct {
    addr: ?*NgSockaddr,
    addrlen: usize,
};

pub const NgPath = extern struct {
    local: NgAddr,
    remote: NgAddr,
    user_data: ?*anyopaque = null,
};

pub const NgPktInfo = extern struct {
    ecn: u8,
    _pad: [7]u8 = @splat(0),
};

pub const NgCloseError = extern struct {
    type_: u32,
    _pad0: u32 = 0,
    error_code: u64,
    frame_type: u64,
    reason: ?[*]const u8,
    reasonlen: usize,
};

pub const NgCryptoConnRef = extern struct {
    get_conn: *const fn (?*NgCryptoConnRef) callconv(.c) ?*NgConn,
    user_data: ?*anyopaque,
};

pub const NgPktHd = extern struct {
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
pub const NG_SETTINGS_SIZE = 184;

pub const NG_SETTINGS_OFF_INITIAL_TS = 48;

pub const NG_TP_SIZE = 344;

pub const NG_TP_OFF_ORIGINAL_DCID = 96;

pub const NG_TP_OFF_MAX_STREAM_DATA_BIDI_LOCAL = 192;

pub const NG_TP_OFF_MAX_STREAM_DATA_BIDI_REMOTE = 200;

pub const NG_TP_OFF_MAX_STREAM_DATA_UNI = 208;

pub const NG_TP_OFF_MAX_DATA = 216;

pub const NG_TP_OFF_MAX_STREAMS_BIDI = 224;

pub const NG_TP_OFF_MAX_STREAMS_UNI = 232;

pub const NG_TP_OFF_MAX_IDLE_TIMEOUT = 240;

pub const NG_TP_OFF_ACTIVE_CID_LIMIT = 256;

pub const NG_CALLBACKS_COUNT = 40;

pub const NgCallbacks = extern struct {
    fields: [NG_CALLBACKS_COUNT]?*const anyopaque,
};

// callback slot indices (V1 layout, offsets verified by C probe)
pub const CB_CLIENT_INITIAL = 0;

pub const CB_RECV_CLIENT_INITIAL = 1;

pub const CB_RECV_CRYPTO_DATA = 2;

pub const CB_HANDSHAKE_COMPLETED = 3;

pub const CB_ENCRYPT = 5;

pub const CB_DECRYPT = 6;

pub const CB_HP_MASK = 7;

pub const CB_RECV_STREAM_DATA = 8;

pub const CB_ACKED_STREAM_DATA_OFFSET = 9;

pub const CB_STREAM_CLOSE = 11;

pub const CB_RECV_RETRY = 13;

pub const CB_RAND = 16;

pub const CB_GET_NEW_CONNECTION_ID = 17;

pub const CB_UPDATE_KEY = 19;

pub const CB_DELETE_CRYPTO_AEAD_CTX = 29;

pub const CB_DELETE_CRYPTO_CIPHER_CTX = 30;

pub const CB_GET_PATH_CHALLENGE_DATA = 34;

pub const CB_VERSION_NEGOTIATION = 36;

pub const RecvStreamDataFn = *const fn (?*NgConn, u32, i64, u64, [*]const u8, usize, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const AckedStreamDataFn = *const fn (?*NgConn, i64, u64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const StreamCloseFn = *const fn (?*NgConn, u32, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const HandshakeCompletedFn = *const fn (?*NgConn, ?*anyopaque) callconv(.c) c_int;

pub const RandFn = *const fn ([*]u8, usize, ?*const anyopaque) callconv(.c) void;

pub const GetNewConnectionIdFn = *const fn (?*NgConn, ?*NgCid, [*]u8, usize, ?*anyopaque) callconv(.c) c_int;

pub const NG_WRITE_STREAM_FLAG_MORE: u32 = 0x01;

pub const NG_WRITE_STREAM_FLAG_FIN: u32 = 0x02;

pub const NG_STREAM_DATA_FLAG_FIN: u32 = 0x01;

pub const NG_ERR_WRITE_MORE: i64 = -240;

pub const NG_PROTO_VER_V1: u32 = 0x0000_0001;

pub const NG_MAX_CIDLEN = 20;

pub const NgApi = struct {
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
pub const GnuSession = opaque {};

pub const GnuCred = opaque {};

pub const GnuDatum = extern struct { data: ?[*]u8, size: c_uint };

pub const GNUTLS_SERVER: c_int = 1;

pub const GNUTLS_CLIENT: c_int = 2;

pub const GNUTLS_CRD_CERTIFICATE: c_int = 1;

pub const GNUTLS_NAME_DNS: c_int = 1;

pub const GNUTLS_X509_FMT_PEM: c_int = 1;

pub const GNUTLS_ALPN_MANDATORY: c_uint = 1;

pub const GTLS_PRIORITY: [*:0]const u8 = "NORMAL:-VERS-ALL:+VERS-TLS1.3:-CIPHER-ALL:+AES-128-GCM:+AES-256-GCM:+CHACHA20-POLY1305:+AES-128-CCM:-GROUP-ALL:+GROUP-SECP256R1:+GROUP-X25519:+GROUP-SECP384R1:+GROUP-SECP521R1:%DISABLE_TLS13_COMPAT_MODE";

pub const GnuApi = struct {
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
pub const H3Conn = opaque {};

pub const H3Rcbuf = opaque {};

pub const H3Vec = extern struct { base: ?[*]u8, len: usize };

pub const H3Settings = extern struct {
    max_field_section_size: u64,
    qpack_max_dtable_capacity: usize,
    qpack_encoder_max_dtable_capacity: usize,
    qpack_blocked_streams: usize,
    enable_connect_protocol: c_int,
    _pad: u32 = 0,
};

pub const H3Nv = extern struct {
    name: ?[*]const u8,
    value: ?[*]const u8,
    namelen: usize,
    valuelen: usize,
    flags: u32,
    _pad: u32 = 0,
};

pub const H3_CALLBACKS_COUNT = 14;

pub const H3Callbacks = extern struct {
    fields: [H3_CALLBACKS_COUNT]?*const anyopaque,
};

pub const H3CB_ACKED_STREAM_DATA = 0;

pub const H3CB_STREAM_CLOSE = 1;

pub const H3CB_RECV_DATA = 2;

pub const H3CB_DEFERRED_CONSUME = 3;

pub const H3CB_BEGIN_HEADERS = 4;

pub const H3CB_RECV_HEADER = 5;

pub const H3CB_END_HEADERS = 6;

pub const H3CB_STOP_SENDING = 10;

pub const H3CB_END_STREAM = 11;

pub const H3CB_RESET_STREAM = 12;

pub const H3AckedFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3StreamCloseFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3RecvDataFn = *const fn (?*H3Conn, i64, [*]const u8, usize, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3BeginHeadersFn = *const fn (?*H3Conn, i64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3RecvHeaderFn = *const fn (?*H3Conn, i64, i32, ?*H3Rcbuf, ?*H3Rcbuf, u8, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3EndHeadersFn = *const fn (?*H3Conn, i64, c_int, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3EndStreamFn = *const fn (?*H3Conn, i64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3StopSendingFn = *const fn (?*H3Conn, i64, u64, ?*anyopaque, ?*anyopaque) callconv(.c) c_int;

pub const H3ReadDataFn = *const fn (?*H3Conn, i64, [*]H3Vec, usize, *u32, ?*anyopaque, ?*anyopaque) callconv(.c) i64;

pub const H3DataReader = extern struct { read_data: ?H3ReadDataFn };

pub const H3_NV_FLAG_NONE: u32 = 0;

pub const H3_DATA_FLAG_EOF: u32 = 0x01;

pub const H3Api = struct {
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
pub var ng_api: ?NgApi = null;

pub var gnu_api: ?GnuApi = null;

pub var h3_api: ?H3Api = null;

pub var api_mutex = std.Io.Mutex.init;

pub fn openFirst(candidates: []const []const u8) ?std.DynLib {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return openFirstNative(candidates);
    }
}

pub fn openFirstNative(candidates: []const []const u8) ?std.DynLib {
    for (candidates) |c| {
        if (std.DynLib.open(c)) |lib| return lib else |_| {}
    }
    return null;
}

pub fn loadNgApi() ?*NgApi {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadNgApiNative();
    }
}

pub fn loadNgApiNative() ?*NgApi {
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

pub fn loadGnuApi() ?*GnuApi {
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

pub fn loadH3Api() ?*H3Api {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadH3ApiNative();
    }
}

pub fn loadH3ApiNative() ?*H3Api {
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

pub fn quicStackAvailable() bool {
    return loadNgApi() != null and loadGnuApi() != null and loadH3Api() != null;
}

// ---- connection objects -------------------------------------------------------
pub const SockStorageWasm = extern struct { bytes: [128]u8 align(8) };

pub const SockStorage = if (builtin.cpu.arch.isWasm()) SockStorageWasm else std.posix.sockaddr.storage;

pub const SockAddrIn = if (builtin.cpu.arch.isWasm()) [16]u8 else std.posix.sockaddr.in;

pub const RawStream = struct {
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

pub const QuicConn = struct {
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

    pub fn path(self: *QuicConn) NgPath {
        return .{
            .local = .{ .addr = @ptrCast(&self.local), .addrlen = self.local_len },
            .remote = .{ .addr = @ptrCast(&self.peer), .addrlen = self.peer_len },
            .user_data = null,
        };
    }
    pub fn sendPacket(self: *QuicConn, bytes: []const u8) void {
        if (self.owns_fd) {
            _ = lxSendTo(self.fd, bytes.ptr, bytes.len, 0, null, 0);
        } else {
            _ = lxSendTo(self.fd, bytes.ptr, bytes.len, 0, &self.peer, self.peer_len);
        }
    }
    pub fn getStream(self: *QuicConn, id: i64) ?*RawStream {
        return self.streams.get(id);
    }
    pub fn ensureStream(self: *QuicConn, id: i64) !*RawStream {
        if (self.streams.get(id)) |s| return s;
        const s = try std.heap.page_allocator.create(RawStream);
        s.* = .{};
        try self.streams.put(std.heap.page_allocator, id, s);
        return s;
    }
};

pub const QuicListener = struct {
    fd: std.posix.fd_t,
    cred: ?*GnuCred = null,
    local: SockStorage = undefined,
    local_len: std.posix.socklen_t = 0,
    pending: std.ArrayListUnmanaged(*QuicConn) = .empty,
    conns: std.ArrayListUnmanaged(*QuicConn) = .empty,
    route: std.AutoHashMapUnmanaged(u64, *QuicConn) = .empty,
};

pub const QuicEndpoint = struct {
    listener: ?*QuicListener = null,
};

// ---- ngtcp2 callbacks ----------------------------------------------------------
pub fn cryptoGetConn(ref: ?*NgCryptoConnRef) callconv(.c) ?*NgConn {
    const r = ref orelse return null;
    const qc: *QuicConn = @ptrCast(@alignCast(r.user_data orelse return null));
    return qc.conn;
}

pub fn cbRand(dest: [*]u8, destlen: usize, ctx: ?*const anyopaque) callconv(.c) void {
    _ = ctx;
    sio.io().random(dest[0..destlen]);
}

pub fn cbGetNewConnectionId(conn: ?*NgConn, cid: ?*NgCid, token: [*]u8, cidlen: usize, user_data: ?*anyopaque) callconv(.c) c_int {
    _ = conn;
    _ = user_data;
    const c = cid orelse return -1;
    if (cidlen > NG_MAX_CIDLEN) return -1;
    sio.io().random(c.data[0..cidlen]);
    c.datalen = cidlen;
    sio.io().random(token[0..16]);
    return 0;
}
