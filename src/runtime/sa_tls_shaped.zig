// TLS client with ClientHello fingerprint shaping for the sci/sa_std
// platform layer (utls-style profiles, backed by OpenSSL via dlopen).
//
// Why a second client next to sa_tls_client.zig (pure-Zig std.crypto)?
// std.crypto.tls offers a fixed ClientHello: no ALPN, no cipher-suite
// selection, no groups/sigalgs control. Fingerprint shaping needs the
// OpenSSL control surface, so this module dlopens libssl exactly like
// sa_tls_server.zig / sa_dtls.zig do.
//
// What a profile controls (applied to a per-connection SSL_CTX):
//   ciphersuites (TLS 1.3 list+order), ciphers (TLS <=1.2 list+order),
//   groups, sigalgs, min/max TLS version, ALPN list, optional private
//   ca_file. Presets: chrome, firefox, safari, go. Unknown profile keys
//   are rejected; `grease:true` returns UNSUPPORTED (OpenSSL does not
//   emit GREASE) instead of silently pretending.
//
// What is NOT shaped: the extension set/order is OpenSSL's own. The
// ground truth of what actually went on the wire is therefore exposed,
// not estimated: a message callback captures the real ClientHello bytes
// during the handshake and hello_ja3 / hello_ja3_string / hello_ja4 are
// computed from those captured bytes. negotiated_json reports the
// negotiated version/cipher/ALPN from the live SSL object.
//
// Trust model matches sa_tls_client.zig: verification is on by default
// (system trust store via SSL_CTX_set_default_verify_paths, or the
// profile's ca_file / ca_pem trust anchors), the hostname is checked
// (SSL_set1_host), and SSL_get_verify_result must be X509_V_OK after the
// handshake. The ONLY opt-out is the profile's explicitly named
// `insecure_skip_verify` flag, which defaults to false and is never
// implied by any other key.
//
// The profile additionally covers the general config surface the census
// specs ask for (Java SSLParameters / Python SSLContext / .NET
// SslClientAuthenticationOptions): `sni` and `verify_host` split the
// server name from the dial host, `cert_file`/`key_file` present a client
// certificate, and `session` (base64 DER) resumes a session previously
// exported with sa_std_tls_shaped_session_blob. Decoded peer certificate
// chains are exposed via sa_std_tls_shaped_peer_cert_chain_json, and
// sa_std_tls_shaped_start_tls upgrades an existing plaintext fd.
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative =
// error; certificate failures are SA_STD_ERR_TLS_VERIFY (-100), matching
// sa_tls_client.zig.

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

// ---- OpenSSL dlopen surface ------------------------------------------------

const SslCtx = opaque {};
const Ssl = opaque {};
const SslMethod = opaque {};
const SslCipher = opaque {};
const Bio = opaque {};
const X509 = opaque {};
const X509Store = opaque {};
const X509Name = opaque {};
const SslStack = opaque {};
const SslSession = opaque {};

const MsgCallback = *const fn (write_p: c_int, version: c_int, content_type: c_int, buf: ?*const anyopaque, len: usize, ssl: ?*Ssl, arg: ?*anyopaque) callconv(.c) void;

const SslApi = struct {
    lib: std.DynLib,
    method_new: *const fn () callconv(.c) ?*const SslMethod,
    ctx_new: *const fn (?*const SslMethod) callconv(.c) ?*SslCtx,
    ctx_free: *const fn (?*SslCtx) callconv(.c) void,
    ctx_set_ciphersuites: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_set_cipher_list: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_set1_groups_list: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_set1_sigalgs_list: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_ctrl: *const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long,
    ctx_set_default_verify_paths: *const fn (?*SslCtx) callconv(.c) c_int,
    ctx_load_verify_locations: *const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int,
    ctx_set_verify: *const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void,
    new: *const fn (?*SslCtx) callconv(.c) ?*Ssl,
    free: *const fn (?*Ssl) callconv(.c) void,
    set_fd: *const fn (?*Ssl, c_int) callconv(.c) c_int,
    ctrl: *const fn (?*Ssl, c_int, c_long, ?*anyopaque) callconv(.c) c_long,
    set_alpn_protos: *const fn (?*Ssl, [*]const u8, c_uint) callconv(.c) c_int,
    set_msg_callback: *const fn (?*Ssl, MsgCallback) callconv(.c) void,
    set_msg_callback_arg: *const fn (?*Ssl, ?*anyopaque) callconv(.c) void,
    set1_host: *const fn (?*Ssl, [*:0]const u8) callconv(.c) c_int,
    connect: *const fn (?*Ssl) callconv(.c) c_int,
    read: *const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int,
    write: *const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int,
    shutdown: *const fn (?*Ssl) callconv(.c) c_int,
    get_error: *const fn (?*const Ssl, c_int) callconv(.c) c_int,
    get_verify_result: *const fn (?*const Ssl) callconv(.c) c_long,
    get_version: *const fn (?*const Ssl) callconv(.c) [*:0]const u8,
    get_current_cipher: *const fn (?*const Ssl) callconv(.c) ?*const SslCipher,
    cipher_get_name: *const fn (?*const SslCipher) callconv(.c) [*:0]const u8,
    get_alpn_selected: *const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void,
    bio_new_mem_buf: *const fn ([*]const u8, c_int) callconv(.c) ?*Bio,
    bio_free: *const fn (?*Bio) callconv(.c) c_int,
    pem_read_bio_x509: *const fn (?*Bio, ?*?*X509, ?*const anyopaque, ?*anyopaque) callconv(.c) ?*X509,
    x509_store_add_cert: *const fn (?*X509Store, ?*X509) callconv(.c) c_int,
    ctx_get_cert_store: *const fn (?*const SslCtx) callconv(.c) ?*X509Store,
    x509_free: *const fn (?*X509) callconv(.c) void,
    get_peer_cert_chain: *const fn (?*const Ssl) callconv(.c) ?*SslStack,
    sk_num: *const fn (?*const SslStack) callconv(.c) c_int,
    sk_value: *const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque,
    i2d_x509: *const fn (?*X509, ?*?[*]u8) callconv(.c) c_int,
    x509_get_subject_name: *const fn (?*const X509) callconv(.c) ?*X509Name,
    x509_get_issuer_name: *const fn (?*const X509) callconv(.c) ?*X509Name,
    x509_name_oneline: *const fn (?*const X509Name, ?[*]u8, c_int) callconv(.c) ?[*:0]u8,
    get1_session: *const fn (?*const Ssl) callconv(.c) ?*SslSession,
    set_session: *const fn (?*Ssl, ?*SslSession) callconv(.c) c_int,
    d2i_session: *const fn (?*?*SslSession, *?[*]const u8, c_long) callconv(.c) ?*SslSession,
    i2d_session: *const fn (?*SslSession, ?*?[*]u8) callconv(.c) c_int,
    session_free: *const fn (?*SslSession) callconv(.c) void,
    session_reused: *const fn (?*const Ssl) callconv(.c) c_int,
    ctx_use_cert_chain_file: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_use_key_file: *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int,
    ctx_check_private_key: *const fn (?*const SslCtx) callconv(.c) c_int,
};

var ssl_api: ?SslApi = null;
var ssl_api_mutex = std.Io.Mutex.init;

fn loadSslApi() ?*SslApi {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadSslApiNative();
    }
}

fn loadSslApiNative() ?*SslApi {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    ssl_api_mutex.lockUncancelable(sio.io());
    defer ssl_api_mutex.unlock(sio.io());
    if (ssl_api) |*api| return api;

    const candidates = [_][]const u8{
        "libssl.so.3",
        "libssl.so",
        "/lib/x86_64-linux-gnu/libssl.so.3",
        "/usr/lib/x86_64-linux-gnu/libssl.so.3",
    };
    var lib: ?std.DynLib = null;
    for (candidates) |c| {
        if (std.DynLib.open(c)) |l| {
            lib = l;
            break;
        } else |_| {}
    }
    var l = lib orelse return null;

    const api = SslApi{
        .lib = l,
        .method_new = l.lookup(*const fn () callconv(.c) ?*const SslMethod, "TLS_client_method") orelse return null,
        .ctx_new = l.lookup(*const fn (?*const SslMethod) callconv(.c) ?*SslCtx, "SSL_CTX_new") orelse return null,
        .ctx_free = l.lookup(*const fn (?*SslCtx) callconv(.c) void, "SSL_CTX_free") orelse return null,
        .ctx_set_ciphersuites = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set_ciphersuites") orelse return null,
        .ctx_set_cipher_list = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set_cipher_list") orelse return null,
        .ctx_set1_groups_list = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set1_groups_list") orelse return null,
        .ctx_set1_sigalgs_list = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set1_sigalgs_list") orelse return null,
        .ctx_ctrl = l.lookup(*const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_CTX_ctrl") orelse return null,
        .ctx_set_default_verify_paths = l.lookup(*const fn (?*SslCtx) callconv(.c) c_int, "SSL_CTX_set_default_verify_paths") orelse return null,
        .ctx_load_verify_locations = l.lookup(*const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int, "SSL_CTX_load_verify_locations") orelse return null,
        .ctx_set_verify = l.lookup(*const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void, "SSL_CTX_set_verify") orelse return null,
        .new = l.lookup(*const fn (?*SslCtx) callconv(.c) ?*Ssl, "SSL_new") orelse return null,
        .free = l.lookup(*const fn (?*Ssl) callconv(.c) void, "SSL_free") orelse return null,
        .set_fd = l.lookup(*const fn (?*Ssl, c_int) callconv(.c) c_int, "SSL_set_fd") orelse return null,
        .ctrl = l.lookup(*const fn (?*Ssl, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_ctrl") orelse return null,
        .set_alpn_protos = l.lookup(*const fn (?*Ssl, [*]const u8, c_uint) callconv(.c) c_int, "SSL_set_alpn_protos") orelse return null,
        .set_msg_callback = l.lookup(*const fn (?*Ssl, MsgCallback) callconv(.c) void, "SSL_set_msg_callback") orelse return null,
        .set_msg_callback_arg = l.lookup(*const fn (?*Ssl, ?*anyopaque) callconv(.c) void, "SSL_set_msg_callback_arg") orelse return null,
        .set1_host = l.lookup(*const fn (?*Ssl, [*:0]const u8) callconv(.c) c_int, "SSL_set1_host") orelse return null,
        .connect = l.lookup(*const fn (?*Ssl) callconv(.c) c_int, "SSL_connect") orelse return null,
        .read = l.lookup(*const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int, "SSL_read") orelse return null,
        .write = l.lookup(*const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int, "SSL_write") orelse return null,
        .shutdown = l.lookup(*const fn (?*Ssl) callconv(.c) c_int, "SSL_shutdown") orelse return null,
        .get_error = l.lookup(*const fn (?*const Ssl, c_int) callconv(.c) c_int, "SSL_get_error") orelse return null,
        .get_verify_result = l.lookup(*const fn (?*const Ssl) callconv(.c) c_long, "SSL_get_verify_result") orelse return null,
        .get_version = l.lookup(*const fn (?*const Ssl) callconv(.c) [*:0]const u8, "SSL_get_version") orelse return null,
        .get_current_cipher = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*const SslCipher, "SSL_get_current_cipher") orelse return null,
        .cipher_get_name = l.lookup(*const fn (?*const SslCipher) callconv(.c) [*:0]const u8, "SSL_CIPHER_get_name") orelse return null,
        .get_alpn_selected = l.lookup(*const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void, "SSL_get0_alpn_selected") orelse return null,
        .bio_new_mem_buf = l.lookup(*const fn ([*]const u8, c_int) callconv(.c) ?*Bio, "BIO_new_mem_buf") orelse return null,
        .bio_free = l.lookup(*const fn (?*Bio) callconv(.c) c_int, "BIO_free") orelse return null,
        .pem_read_bio_x509 = l.lookup(*const fn (?*Bio, ?*?*X509, ?*const anyopaque, ?*anyopaque) callconv(.c) ?*X509, "PEM_read_bio_X509") orelse return null,
        .x509_store_add_cert = l.lookup(*const fn (?*X509Store, ?*X509) callconv(.c) c_int, "X509_STORE_add_cert") orelse return null,
        .ctx_get_cert_store = l.lookup(*const fn (?*const SslCtx) callconv(.c) ?*X509Store, "SSL_CTX_get_cert_store") orelse return null,
        .x509_free = l.lookup(*const fn (?*X509) callconv(.c) void, "X509_free") orelse return null,
        .get_peer_cert_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get_peer_cert_chain") orelse return null,
        .sk_num = l.lookup(*const fn (?*const SslStack) callconv(.c) c_int, "OPENSSL_sk_num") orelse return null,
        .sk_value = l.lookup(*const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque, "OPENSSL_sk_value") orelse return null,
        .i2d_x509 = l.lookup(*const fn (?*X509, ?*?[*]u8) callconv(.c) c_int, "i2d_X509") orelse return null,
        .x509_get_subject_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_subject_name") orelse return null,
        .x509_get_issuer_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_issuer_name") orelse return null,
        .x509_name_oneline = l.lookup(*const fn (?*const X509Name, ?[*]u8, c_int) callconv(.c) ?[*:0]u8, "X509_NAME_oneline") orelse return null,
        .get1_session = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslSession, "SSL_get1_session") orelse return null,
        .set_session = l.lookup(*const fn (?*Ssl, ?*SslSession) callconv(.c) c_int, "SSL_set_session") orelse return null,
        .d2i_session = l.lookup(*const fn (?*?*SslSession, *?[*]const u8, c_long) callconv(.c) ?*SslSession, "d2i_SSL_SESSION") orelse return null,
        .i2d_session = l.lookup(*const fn (?*SslSession, ?*?[*]u8) callconv(.c) c_int, "i2d_SSL_SESSION") orelse return null,
        .session_free = l.lookup(*const fn (?*SslSession) callconv(.c) void, "SSL_SESSION_free") orelse return null,
        .session_reused = l.lookup(*const fn (?*const Ssl) callconv(.c) c_int, "SSL_session_reused") orelse return null,
        .ctx_use_cert_chain_file = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_use_certificate_chain_file") orelse return null,
        .ctx_use_key_file = l.lookup(*const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int, "SSL_CTX_use_PrivateKey_file") orelse return null,
        .ctx_check_private_key = l.lookup(*const fn (?*const SslCtx) callconv(.c) c_int, "SSL_CTX_check_private_key") orelse return null,
    };
    ssl_api = api;
    return &ssl_api.?;
}

// SSL_CTRL_SET_TLSEXT_HOSTNAME / TLSEXT_NAMETYPE_host_name
const SSL_CTRL_SET_TLSEXT_HOSTNAME: c_int = 55;
// SSL_CTX ctrl ids for proto version bounds
const SSL_CTRL_SET_MIN_PROTO_VERSION: c_int = 123;
const SSL_CTRL_SET_MAX_PROTO_VERSION: c_int = 124;
const SSL_VERIFY_PEER: c_int = 0x01;
const SSL_FILETYPE_PEM: c_int = 1;
const SSL_ERROR_ZERO_RETURN: c_int = 6;

// ---- profiles ---------------------------------------------------------------

const Profile = struct {
    preset: ?[]const u8 = null,
    alpn: ?[]const []const u8 = null,
    ciphersuites: ?[]const u8 = null,
    ciphers: ?[]const u8 = null,
    groups: ?[]const u8 = null,
    sigalgs: ?[]const u8 = null,
    min_version: ?[]const u8 = null,
    max_version: ?[]const u8 = null,
    ca_file: ?[]const u8 = null,
    ca_pem: ?[]const u8 = null,
    sni: ?[]const u8 = null,
    verify_host: ?[]const u8 = null,
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    insecure_skip_verify: bool = false,
    session: ?[]const u8 = null,
    grease: bool = false,
};

const Effective = struct {
    alpn: []const []const u8 = &.{},
    ciphersuites: ?[]const u8 = null,
    ciphers: ?[]const u8 = null,
    groups: ?[]const u8 = null,
    sigalgs: ?[]const u8 = null,
    min_version: ?[]const u8 = null,
    max_version: ?[]const u8 = null,
    ca_file: ?[]const u8 = null,
    ca_pem: ?[]const u8 = null,
    sni: ?[]const u8 = null,
    verify_host: ?[]const u8 = null,
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    insecure_skip_verify: bool = false,
    session_der: ?[]const u8 = null,
};

const TLS13_SUITES = "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256";
const BROWSER_SIGALGS = "ecdsa_secp256r1_sha256:rsa_pss_rsae_sha256:rsa_pkcs1_sha256:ecdsa_secp384r1_sha384:rsa_pss_rsae_sha384:rsa_pkcs1_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha512";

fn presetEffective(name: []const u8) ?Effective {
    if (std.mem.eql(u8, name, "chrome")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA",
            .groups = "X25519:P-256:P-384",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "firefox")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA",
            .groups = "X25519:P-256:P-384:P-521:ffdhe2048:ffdhe3072",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "safari")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA:AES128-SHA",
            .groups = "X25519:P-256:P-384:P-521",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "go")) {
        return .{
            .alpn = &.{},
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA",
            .groups = "X25519:P-256:P-384:P-521",
            .sigalgs = "ecdsa_secp256r1_sha256:ecdsa_secp384r1_sha384:ecdsa_secp521r1_sha512:rsa_pss_rsae_sha256:rsa_pss_rsae_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha256:rsa_pkcs1_sha384:rsa_pkcs1_sha512",
        };
    }
    if (std.mem.eql(u8, name, "default")) return .{};
    return null;
}

fn versionConst(name: []const u8) ?c_long {
    if (std.mem.eql(u8, name, "1.0")) return 0x0301;
    if (std.mem.eql(u8, name, "1.1")) return 0x0302;
    if (std.mem.eql(u8, name, "1.2")) return 0x0303;
    if (std.mem.eql(u8, name, "1.3")) return 0x0304;
    return null;
}

// Merge a parsed profile over its preset and validate it. The returned
// Effective borrows strings from `p` (and static preset literals), so the
// caller must keep the parsed document alive while applying it.
const ResolveResult = union(enum) { ok: Effective, err: i32 };

fn effectiveFromProfile(p: *const Profile) ResolveResult {
    if (p.grease) return .{ .err = SA_STD_ERR_UNSUPPORTED };
    var eff: Effective = .{};
    if (p.preset) |name| {
        eff = presetEffective(name) orelse return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    }
    if (p.alpn) |v| eff.alpn = v;
    if (p.ciphersuites) |v| eff.ciphersuites = v;
    if (p.ciphers) |v| eff.ciphers = v;
    if (p.groups) |v| eff.groups = v;
    if (p.sigalgs) |v| eff.sigalgs = v;
    if (p.min_version) |v| {
        if (versionConst(v) == null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.min_version = v;
    }
    if (p.max_version) |v| {
        if (versionConst(v) == null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.max_version = v;
    }
    if (p.ca_file) |v| eff.ca_file = v;
    if (p.ca_pem) |v| eff.ca_pem = v;
    if (eff.ca_file != null and eff.ca_pem != null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    if (p.sni) |v| {
        if (v.len == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.sni = v;
    }
    if (p.verify_host) |v| {
        if (v.len == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.verify_host = v;
    }
    if (p.cert_file) |v| eff.cert_file = v;
    if (p.key_file) |v| eff.key_file = v;
    if ((eff.cert_file == null) != (eff.key_file == null)) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    eff.insecure_skip_verify = p.insecure_skip_verify;
    if (p.session) |v| {
        // The blob travels as base64 DER (from sa_std_tls_shaped_session_blob);
        // decode once here so a malformed blob fails before any dial.
        const dec = std.base64.standard.decoderWithIgnore(" \t\r\n");
        const buf = std.heap.page_allocator.alloc(u8, v.len) catch return .{ .err = SA_STD_ERR_NO_MEMORY };
        defer std.heap.page_allocator.free(buf);
        const n = dec.decode(buf, v) catch return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        if (n == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.session_der = std.heap.page_allocator.dupe(u8, buf[0..n]) catch return .{ .err = SA_STD_ERR_NO_MEMORY };
    }
    return .{ .ok = eff };
}

// ---- connection handle ------------------------------------------------------

const hello_cap = 65536;

const ShapedHandle = struct {
    ssl: *Ssl,
    ctx: *SslCtx,
    stream: std.Io.net.Stream,
    host: []u8,
    hello_buf: []u8,
    hello_len: usize = 0,
    hello_truncated: bool = false,
};

fn msgCallback(write_p: c_int, version: c_int, content_type: c_int, buf: ?*const anyopaque, len: usize, ssl: ?*Ssl, arg: ?*anyopaque) callconv(.c) void {
    _ = version;
    _ = ssl;
    _ = content_type;
    if (write_p != 1) return;
    const h: *ShapedHandle = @ptrCast(@alignCast(arg orelse return));
    if (h.hello_len != 0) return; // first ClientHello only
    const bytes: [*]const u8 = @ptrCast(buf orelse return);
    // The only client-originated handshake message starting with type 1
    // is the ClientHello (Finished is 20, KeyUpdate is 24).
    if (len < 40 or bytes[0] != 1) return;
    const take = @min(len, h.hello_buf.len);
    @memcpy(h.hello_buf[0..take], bytes[0..take]);
    h.hello_len = take;
    h.hello_truncated = len > take;
}

fn dialHost(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

fn toZ(alloc: std.mem.Allocator, s: []const u8) ?[:0]u8 {
    const z = alloc.allocSentinel(u8, s.len, 0) catch return null;
    @memcpy(z, s);
    return z;
}

// ---- exported surface -------------------------------------------------------

pub export fn sa_std_tls_shaped_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (loadSslApi() != null) 1 else 0;
    return SA_STD_OK;
}

pub export fn sa_std_tls_shaped_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, profile_ptr: ?[*]const u8, profile_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const host_n = u64ToUsize(host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const host_slice = if (host_ptr) |p| p[0..host_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;
    const profile_json: []const u8 = if (profile_ptr) |p| p[0..(u64ToUsize(profile_len) orelse return SA_STD_ERR_INVALID_ARGUMENT)] else "";

    // Parse + resolve the profile; the parsed document stays alive until
    // doConnect returns (Effective borrows its strings).
    var parsed: ?std.json.Parsed(Profile) = null;
    defer if (parsed) |*pp| pp.deinit();
    var eff: Effective = .{};
    if (profile_json.len != 0) {
        parsed = std.json.parseFromSlice(Profile, std.heap.page_allocator, profile_json, .{ .ignore_unknown_fields = false }) catch {
            return SA_STD_ERR_INVALID_ARGUMENT;
        };
        switch (effectiveFromProfile(&parsed.?.value)) {
            .ok => |e| eff = e,
            .err => |code| return code,
        }
    }

    defer if (eff.session_der) |d| std.heap.page_allocator.free(d);
    const h = doConnect(api, host_slice, @intCast(port), &eff) catch |err| {
        return switch (err) {
            error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
            error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            error.TlsVerify => SA_STD_ERR_TLS_VERIFY,
            error.Unsupported => SA_STD_ERR_UNSUPPORTED,
            else => SA_STD_ERR_IO,
        };
    };
    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

const ConnectError = error{ InvalidArgument, OutOfMemory, TlsVerify, Unsupported, Io };

/// Load every certificate in a PEM blob into the ctx trust store. Returns
/// false when the blob yields no usable certificate (loud failure at the
/// call site, never a silent empty store).
fn loadCaPemIntoStore(api: *SslApi, ctx: *SslCtx, pem: []const u8) bool {
    const store = api.ctx_get_cert_store(ctx) orelse return false;
    const bio = api.bio_new_mem_buf(pem.ptr, @intCast(@min(pem.len, @as(usize, @intCast(std.math.maxInt(c_int)))))) orelse return false;
    defer _ = api.bio_free(bio);
    var count: usize = 0;
    while (true) {
        const x = api.pem_read_bio_x509(bio, null, null, null) orelse break;
        defer api.x509_free(x);
        if (api.x509_store_add_cert(store, x) != 1) return false;
        count += 1;
    }
    return count > 0;
}

fn doConnect(api: *SslApi, host_slice: []const u8, port: u16, eff: *const Effective) ConnectError!*ShapedHandle {
    const stream = dialHost(host_slice, port) catch return ConnectError.Io;
    return doConnectOnStream(api, stream, host_slice, eff);
}

/// Handshake core shared by connect and start_tls: takes ownership of
/// `stream` (the errdefer chain closes it on every failure path).
fn doConnectOnStream(api: *SslApi, stream: std.Io.net.Stream, host_slice: []const u8, eff: *const Effective) ConnectError!*ShapedHandle {
    const alloc = std.heap.page_allocator;
    errdefer stream.close(sio.io());

    const method = api.method_new() orelse return ConnectError.Unsupported;
    const ctx = api.ctx_new(method) orelse return ConnectError.Io;
    errdefer api.ctx_free(ctx);

    // Fingerprint shaping on the context.
    if (eff.ciphersuites) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set_ciphersuites(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.ciphers) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set_cipher_list(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.groups) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set1_groups_list(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.sigalgs) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_set1_sigalgs_list(ctx, z.ptr) != 1) return ConnectError.InvalidArgument;
    }
    // Client certificate presentation (mutual TLS): both files or neither
    // (validated in effectiveFromProfile).
    if (eff.cert_file) |cf| {
        const cz = toZ(alloc, cf) orelse return ConnectError.OutOfMemory;
        defer alloc.free(cz);
        if (api.ctx_use_cert_chain_file(ctx, cz.ptr) != 1) return ConnectError.Io;
        const kz = toZ(alloc, eff.key_file.?) orelse return ConnectError.OutOfMemory;
        defer alloc.free(kz);
        if (api.ctx_use_key_file(ctx, kz.ptr, SSL_FILETYPE_PEM) != 1) return ConnectError.Io;
        if (api.ctx_check_private_key(ctx) != 1) return ConnectError.Io;
    }
    if (eff.min_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.max_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }

    // Verification modes. Default: on, system store. ca_file / ca_pem
    // REPLACE the store with explicit private anchors (loopback tests,
    // private PKI). insecure_skip_verify -- and only that explicitly named
    // flag -- turns verification off entirely.
    if (eff.insecure_skip_verify) {
        api.ctx_set_verify(ctx, 0, null);
    } else if (eff.ca_pem) |v| {
        if (!loadCaPemIntoStore(api, ctx, v)) return ConnectError.InvalidArgument;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    } else if (eff.ca_file) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_load_verify_locations(ctx, z.ptr, null) != 1) return ConnectError.Io;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    } else {
        if (api.ctx_set_default_verify_paths(ctx) != 1) return ConnectError.Io;
        api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);
    }

    const ssl = api.new(ctx) orelse return ConnectError.Io;
    errdefer api.free(ssl);

    // SNI and the verification name split from the dial host when the
    // profile asks (CDN / IP-direct connects): verify_host wins for the
    // certificate check, then sni, then the dial host; SNI uses sni, then
    // the dial host. In insecure mode there is no name check at all.
    const verify_name: []const u8 = eff.verify_host orelse eff.sni orelse host_slice;
    const sni_name: []const u8 = eff.sni orelse host_slice;
    if (!eff.insecure_skip_verify) {
        const vz = toZ(alloc, verify_name) orelse return ConnectError.OutOfMemory;
        defer alloc.free(vz);
        if (api.set1_host(ssl, vz.ptr) != 1) return ConnectError.InvalidArgument;
    }
    {
        const sz = toZ(alloc, sni_name) orelse return ConnectError.OutOfMemory;
        defer alloc.free(sz);
        _ = api.ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, @ptrCast(@constCast(sz.ptr)));
    }

    if (eff.alpn.len > 0) {
        var wire: [512]u8 = undefined;
        var off: usize = 0;
        for (eff.alpn) |proto| {
            if (proto.len == 0 or proto.len > 255) return ConnectError.InvalidArgument;
            if (off + 1 + proto.len > wire.len) return ConnectError.InvalidArgument;
            wire[off] = @intCast(proto.len);
            off += 1;
            @memcpy(wire[off..][0..proto.len], proto);
            off += proto.len;
        }
        if (api.set_alpn_protos(ssl, &wire, @intCast(off)) != 0) return ConnectError.InvalidArgument;
    }

    if (api.set_fd(ssl, stream.socket.handle) != 1) return ConnectError.Io;

    // Opportunistic session resumption: a malformed blob is a loud
    // argument error; a server that declines to resume simply produces a
    // full handshake (that is TLS semantics, not a verification change).
    if (eff.session_der) |der| {
        var p: ?[*]const u8 = der.ptr;
        const sess = api.d2i_session(null, &p, @intCast(der.len)) orelse return ConnectError.InvalidArgument;
        defer api.session_free(sess);
        if (api.set_session(ssl, sess) != 1) return ConnectError.InvalidArgument;
    }

    const host_owned = alloc.dupe(u8, host_slice) catch return ConnectError.OutOfMemory;
    errdefer alloc.free(host_owned);
    const hello_buf = alloc.alloc(u8, hello_cap) catch return ConnectError.OutOfMemory;
    errdefer alloc.free(hello_buf);
    const h = alloc.create(ShapedHandle) catch return ConnectError.OutOfMemory;
    errdefer alloc.destroy(h);
    h.* = .{
        .ssl = ssl,
        .ctx = ctx,
        .stream = stream,
        .host = host_owned,
        .hello_buf = hello_buf,
    };
    api.set_msg_callback(ssl, &msgCallback);
    api.set_msg_callback_arg(ssl, h);

    if (api.connect(ssl) != 1) {
        if (eff.insecure_skip_verify) return ConnectError.Io;
        const vrc = api.get_verify_result(ssl);
        return if (vrc != 0) ConnectError.TlsVerify else ConnectError.Io;
    }
    if (!eff.insecure_skip_verify and api.get_verify_result(ssl) != 0) return ConnectError.TlsVerify;
    return h;
}

fn freeHandle(h: *ShapedHandle) void {
    const api = loadSslApi() orelse return;
    _ = api.shutdown(h.ssl);
    api.free(h.ssl);
    api.ctx_free(h.ctx);
    h.stream.close(sio.io());
    std.heap.page_allocator.free(h.host);
    std.heap.page_allocator.free(h.hello_buf);
    std.heap.page_allocator.destroy(h);
}

fn handleFromU64(handle: u64) ?*ShapedHandle {
    if (handle == 0) return null;
    const p: *ShapedHandle = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

pub export fn sa_std_tls_shaped_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const slot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const h = handleFromU64(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const cap_c: c_int = @intCast(@min(cap, @as(u64, @intCast(std.math.maxInt(c_int)))));
    if (cap_c == 0) return SA_STD_OK;
    const rc = api.read(h.ssl, buf, cap_c);
    if (rc > 0) {
        slot.* = @intCast(rc);
        return SA_STD_OK;
    }
    if (api.get_error(h.ssl, rc) == SSL_ERROR_ZERO_RETURN) return SA_STD_OK; // clean EOF
    return SA_STD_ERR_IO;
}

pub export fn sa_std_tls_shaped_write(handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const h = handleFromU64(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const src = buf orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const chunk = src[0..@min(len, @as(u64, @intCast(std.math.maxInt(c_int))))];
    const rc = api.write(h.ssl, chunk.ptr, @intCast(chunk.len));
    if (rc <= 0) return SA_STD_ERR_IO;
    slot.* = @intCast(rc);
    return SA_STD_OK;
}

pub export fn sa_std_tls_shaped_close(handle: u64) i32 {
    const h = handleFromU64(handle) orelse return SA_STD_OK;
    freeHandle(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_shaped_negotiated_json(handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const h = handleFromU64(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const version = std.mem.span(api.get_version(h.ssl));
    const cipher_ptr = api.get_current_cipher(h.ssl);
    const cipher = if (cipher_ptr) |c| std.mem.span(api.cipher_get_name(c)) else "NONE";
    var alpn_data: ?[*]const u8 = null;
    var alpn_len: c_uint = 0;
    api.get_alpn_selected(h.ssl, &alpn_data, &alpn_len);
    const alpn: []const u8 = if (alpn_data) |d| d[0..alpn_len] else "";
    const reused: []const u8 = if (api.session_reused(h.ssl) != 0) "true" else "false";
    var buffer: [640]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"version\":\"{s}\",\"cipher\":\"{s}\",\"alpn\":\"{s}\",\"session_reused\":{s}}}", .{ version, cipher, alpn, reused }) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}


// ---- STARTTLS upgrade ---------------------------------------------------------

/// Upgrade an existing plaintext TCP connection (raw fd) to TLS using a
/// profile, returning a normal shaped handle. The fd's ownership transfers
/// to this call: it is closed on failure and owned by the handle on
/// success. `host` is not dialed -- it supplies the default SNI /
/// verification name (the profile's sni / verify_host keys override).
pub export fn sa_std_tls_shaped_start_tls(fd: i32, host_ptr: ?[*]const u8, host_len: u64, profile_ptr: ?[*]const u8, profile_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (comptime builtin.os.tag == .windows) return SA_STD_ERR_UNSUPPORTED;
    if (fd < 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const host_n = u64ToUsize(host_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const host_slice = if (host_ptr) |p| p[0..host_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const profile_json: []const u8 = if (profile_ptr) |p| p[0..(u64ToUsize(profile_len) orelse return SA_STD_ERR_INVALID_ARGUMENT)] else "";

    var parsed: ?std.json.Parsed(Profile) = null;
    defer if (parsed) |*pp| pp.deinit();
    var eff: Effective = .{};
    if (profile_json.len != 0) {
        parsed = std.json.parseFromSlice(Profile, std.heap.page_allocator, profile_json, .{ .ignore_unknown_fields = false }) catch {
            return SA_STD_ERR_INVALID_ARGUMENT;
        };
        switch (effectiveFromProfile(&parsed.?.value)) {
            .ok => |e| eff = e,
            .err => |code| return code,
        }
    }
    defer if (eff.session_der) |d| std.heap.page_allocator.free(d);

    const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", 0) catch return SA_STD_ERR_IO;
    const stream = std.Io.net.Stream{ .socket = .{ .handle = @intCast(fd), .address = addr } };
    const h = doConnectOnStream(api, stream, host_slice, &eff) catch |err| {
        return switch (err) {
            error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
            error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            error.TlsVerify => SA_STD_ERR_TLS_VERIFY,
            error.Unsupported => SA_STD_ERR_UNSUPPORTED,
            else => SA_STD_ERR_IO,
        };
    };
    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

// ---- session export -----------------------------------------------------------

/// Serialize the connection's current session as base64 DER, suitable for
/// the profile `session` key of a later connect. Returns
/// SA_STD_ERR_UNSUPPORTED on TLS 1.3 connections whose session ticket has
/// not arrived yet (there is no resumable session to export at that point;
/// with TLS 1.2 a session is always available after the handshake).
pub export fn sa_std_tls_shaped_session_blob(handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const h = handleFromU64(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const sess = api.get1_session(h.ssl) orelse return SA_STD_ERR_UNSUPPORTED;
    defer api.session_free(sess);
    const len = api.i2d_session(sess, null);
    if (len <= 0) return SA_STD_ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const der = alloc.alloc(u8, @intCast(len)) catch return SA_STD_ERR_NO_MEMORY;
    defer alloc.free(der);
    var p: ?[*]u8 = der.ptr;
    if (api.i2d_session(sess, &p) != len) return SA_STD_ERR_IO;
    const enc = std.base64.standard.Encoder;
    const b64 = alloc.alloc(u8, enc.calcSize(der.len)) catch return SA_STD_ERR_NO_MEMORY;
    _ = enc.encode(b64, der);
    return registerString(b64, slot);
}

// ---- peer certificate chain (decoded) ------------------------------------------

fn appendJsonEscaped(list: *std.ArrayList(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try list.appendSlice(alloc, "\\\""),
            '\\' => try list.appendSlice(alloc, "\\\\"),
            '\n' => try list.appendSlice(alloc, "\\n"),
            '\r' => try list.appendSlice(alloc, "\\r"),
            '\t' => try list.appendSlice(alloc, "\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                var tmp: [8]u8 = undefined;
                const t = try std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{ch});
                try list.appendSlice(alloc, t);
            },
            else => try list.append(alloc, ch),
        }
    }
}

fn appendHexUpper(list: *std.ArrayList(u8), alloc: std.mem.Allocator, bytes: []const u8, colon: bool) !void {
    const digits = "0123456789ABCDEF";
    for (bytes, 0..) |b, i| {
        if (colon and i != 0) try list.append(alloc, ':');
        try list.append(alloc, digits[b >> 4]);
        try list.append(alloc, digits[b & 0x0f]);
    }
}

/// Serial number (INTEGER content bytes, hex) from the certificate DER:
/// outer SEQUENCE -> TBS SEQUENCE -> optional [0] version -> INTEGER.
fn serialHex(alloc: std.mem.Allocator, der_bytes: []const u8) !?[]u8 {
    const der = std.crypto.Certificate.der;
    const outer = der.Element.parse(der_bytes, 0) catch return null;
    const tbs = der.Element.parse(der_bytes, outer.slice.start) catch return null;
    var idx = tbs.slice.start;
    var el = der.Element.parse(der_bytes, idx) catch return null;
    if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 0) {
        idx = el.slice.end;
        el = der.Element.parse(der_bytes, idx) catch return null;
    }
    if (el.identifier.class != .universal or @intFromEnum(el.identifier.tag) != 2) return null;
    const bytes = der_bytes[el.slice.start..el.slice.end];
    var out = try alloc.alloc(u8, bytes.len * 2);
    errdefer alloc.free(out);
    const digits = "0123456789ABCDEF";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0x0f];
    }
    return out;
}

/// Collect dNSName / iPAddress entries from the parsed SAN extension.
fn collectSans(parsed: *const std.crypto.Certificate.Parsed, dns: *std.ArrayList([]const u8), ips: *std.ArrayList([]const u8), alloc: std.mem.Allocator) !void {
    const der = std.crypto.Certificate.der;
    const san = parsed.subjectAltName();
    if (san.len == 0) return;
    const seq = der.Element.parse(san, 0) catch return;
    var idx = seq.slice.start;
    while (idx < seq.slice.end) {
        const el = der.Element.parse(san, idx) catch break;
        const content = san[el.slice.start..el.slice.end];
        if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 2) {
            try dns.append(alloc, content);
        } else if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 7) {
            try ips.append(alloc, content);
        }
        idx = el.slice.end;
    }
}

/// JSON document for a peer chain: one entry per certificate, leaf first,
/// with decoded subject/issuer (OpenSSL oneline form), common name, SAN
/// dNSName/iPAddress lists, validity window (unix seconds), serial (hex)
/// and the SHA-256 fingerprint (openssl colon-hex form). Certificates the
/// std DER parser cannot decode are still listed (names + fingerprint)
/// with "fields_parsed":false -- never silently dropped.
fn buildPeerCertChainJson(api: *SslApi, ssl: *Ssl) ![]u8 {
    const alloc = std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "{\"certificates\":[");
    var first = true;
    if (api.get_peer_cert_chain(ssl)) |chain| {
        const n = api.sk_num(chain);
        var i: c_int = 0;
        while (i < n) : (i += 1) {
            const raw = api.sk_value(chain, i) orelse continue;
            const x: *X509 = @ptrCast(@alignCast(raw));
            const dlen = api.i2d_x509(x, null);
            if (dlen <= 0) continue;
            const derbuf = try alloc.alloc(u8, @intCast(dlen));
            defer alloc.free(derbuf);
            var p: ?[*]u8 = derbuf.ptr;
            if (api.i2d_x509(x, &p) != dlen) continue;

            if (!first) try out.append(alloc, ',');
            first = false;
            try out.append(alloc, '{');
            var name_buf: [1024]u8 = undefined;
            try out.appendSlice(alloc, "\"subject\":\"");
            if (api.x509_name_oneline(api.x509_get_subject_name(x), &name_buf, @intCast(name_buf.len))) |s| try appendJsonEscaped(&out, alloc, std.mem.span(s));
            try out.appendSlice(alloc, "\",\"issuer\":\"");
            if (api.x509_name_oneline(api.x509_get_issuer_name(x), &name_buf, @intCast(name_buf.len))) |s| try appendJsonEscaped(&out, alloc, std.mem.span(s));
            try out.appendSlice(alloc, "\",\"sha256_fingerprint\":\"");
            var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(derbuf, &digest, .{});
            try appendHexUpper(&out, alloc, &digest, true);
            try out.append(alloc, '"');

            const cert = std.crypto.Certificate{ .buffer = derbuf, .index = 0 };
            if (cert.parse()) |parsed| {
                var dns: std.ArrayList([]const u8) = .empty;
                defer dns.deinit(alloc);
                var ips: std.ArrayList([]const u8) = .empty;
                defer ips.deinit(alloc);
                try collectSans(&parsed, &dns, &ips, alloc);
                try out.appendSlice(alloc, ",\"common_name\":\"");
                try appendJsonEscaped(&out, alloc, parsed.commonName());
                try out.appendSlice(alloc, "\",\"san_dns\":[");
                for (dns.items, 0..) |name, j| {
                    if (j != 0) try out.append(alloc, ',');
                    try out.append(alloc, '"');
                    try appendJsonEscaped(&out, alloc, name);
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, "],\"san_ip\":[");
                for (ips.items, 0..) |ip, j| {
                    if (j != 0) try out.append(alloc, ',');
                    try out.append(alloc, '"');
                    if (ip.len == 4) {
                        var tmp: [24]u8 = undefined;
                        const t = try std.fmt.bufPrint(&tmp, "{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] });
                        try out.appendSlice(alloc, t);
                    } else {
                        try appendHexUpper(&out, alloc, ip, true);
                    }
                    try out.append(alloc, '"');
                }
                var num_buf: [64]u8 = undefined;
                try out.appendSlice(alloc, "],\"not_before\":");
                try out.appendSlice(alloc, try std.fmt.bufPrint(&num_buf, "{d}", .{parsed.validity.not_before}));
                try out.appendSlice(alloc, ",\"not_after\":");
                try out.appendSlice(alloc, try std.fmt.bufPrint(&num_buf, "{d}", .{parsed.validity.not_after}));
                try out.appendSlice(alloc, ",\"serial_hex\":\"");
                if (try serialHex(alloc, derbuf)) |sh| {
                    defer alloc.free(sh);
                    try out.appendSlice(alloc, sh);
                }
                try out.append(alloc, '"');
            } else |_| {
                try out.appendSlice(alloc, ",\"fields_parsed\":false");
            }
            try out.append(alloc, '}');
        }
    }
    try out.appendSlice(alloc, "]}");
    return out.toOwnedSlice(alloc);
}

pub export fn sa_std_tls_shaped_peer_cert_chain_json(handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const h = handleFromU64(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const json = buildPeerCertChainJson(api, h.ssl) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(json, slot);
}

// ---- buffer handle registry (same shape as sa_tls_client.zig) --------------

var string_registry_mutex = std.Io.Mutex.init;
var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

fn registerString(bytes: []u8, slot: *u64) i32 {
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    var i: usize = 0;
    while (i < string_registry.items.len) : (i += 1) {
        if (string_registry.items[i] == null) {
            string_registry.items[i] = bytes;
            slot.* = @intCast(i + 1);
            return SA_STD_OK;
        }
    }
    string_registry.append(std.heap.page_allocator, bytes) catch {
        std.heap.page_allocator.free(bytes);
        return SA_STD_ERR_NO_MEMORY;
    };
    slot.* = @intCast(string_registry.items.len);
    return SA_STD_OK;
}

fn takeString(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return null;
    return string_registry.items[idx];
}

pub export fn sa_std_tls_shaped_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeString(handle) orelse return null;
    return s.ptr;
}

pub export fn sa_std_tls_shaped_buffer_len(handle: u64) u64 {
    const s = takeString(handle) orelse return 0;
    return @intCast(s.len);
}

pub export fn sa_std_tls_shaped_buffer_free(handle: u64) i32 {
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

// ---- ClientHello parsing + JA3/JA4 over the captured bytes ------------------

const SA_STD_ERR_TRUNCATED: i32 = 9; // matches sa_std.zig's value

fn writeOut(out: ?[*]u8, out_cap: u64, out_len: ?*u64, bytes: []const u8) i32 {
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

fn isGrease(v: u16) bool {
    return (v & 0x00ff) == (v >> 8) and (v & 0x000f) == 0x000a;
}

const HelloInfo = struct {
    legacy_version: u16 = 0,
    ciphers: [128]u16 = undefined,
    cipher_count: usize = 0,
    extensions: [128]u16 = undefined,
    extension_count: usize = 0,
    curves: [64]u16 = undefined,
    curve_count: usize = 0,
    point_formats: [32]u8 = undefined,
    point_format_count: usize = 0,
    supported_versions: [16]u16 = undefined,
    supported_version_count: usize = 0,
    sigalgs: [64]u16 = undefined,
    sigalg_count: usize = 0,
    has_sni: bool = false,
    alpn_first_char: u8 = 0,
    alpn_last_char: u8 = 0,
};

const Reader = struct {
    b: []const u8,
    i: usize = 0,
    fn u8v(r: *Reader) ?u8 {
        if (r.i + 1 > r.b.len) return null;
        defer r.i += 1;
        return r.b[r.i];
    }
    fn u16v(r: *Reader) ?u16 {
        if (r.i + 2 > r.b.len) return null;
        defer r.i += 2;
        return std.mem.readInt(u16, r.b[r.i..][0..2], .big);
    }
    fn skip(r: *Reader, n: usize) ?void {
        if (r.i + n > r.b.len) return null;
        r.i += n;
    }
    fn take(r: *Reader, n: usize) ?[]const u8 {
        if (r.i + n > r.b.len) return null;
        defer r.i += n;
        return r.b[r.i..][0..n];
    }
};

fn parseHello(msg: []const u8) ?HelloInfo {
    var info = HelloInfo{};
    var r = Reader{ .b = msg };
    const mtype = r.u8v() orelse return null;
    if (mtype != 1) return null; // msg type ClientHello
    _ = r.u8v() orelse return null; // length (3 bytes)
    _ = r.u8v() orelse return null;
    _ = r.u8v() orelse return null;
    info.legacy_version = r.u16v() orelse return null;
    r.skip(32) orelse return null; // random
    const sid_len = r.u8v() orelse return null;
    r.skip(sid_len) orelse return null;
    const cipher_len = r.u16v() orelse return null;
    const cipher_bytes = r.take(cipher_len) orelse return null;
    var ci: usize = 0;
    while (ci + 2 <= cipher_bytes.len) : (ci += 2) {
        const v = std.mem.readInt(u16, cipher_bytes[ci..][0..2], .big);
        if (isGrease(v)) continue;
        if (info.cipher_count < info.ciphers.len) {
            info.ciphers[info.cipher_count] = v;
            info.cipher_count += 1;
        }
    }
    const comp_len = r.u8v() orelse return null;
    r.skip(comp_len) orelse return null;
    if (r.i >= r.b.len) return info; // extensions are optional on the wire
    const ext_total = r.u16v() orelse return null;
    const ext_bytes = r.take(ext_total) orelse return null;
    var er = Reader{ .b = ext_bytes };
    while (er.i + 4 <= ext_bytes.len) {
        const etype = er.u16v() orelse break;
        const elen = er.u16v() orelse break;
        const edata = er.take(elen) orelse break;
        if (!isGrease(etype)) {
            if (info.extension_count < info.extensions.len) {
                info.extensions[info.extension_count] = etype;
                info.extension_count += 1;
            }
        }
        switch (etype) {
            0 => info.has_sni = true,
            10 => {
                var gr = Reader{ .b = edata };
                const glen = gr.u16v() orelse continue;
                const gbytes = gr.take(glen) orelse continue;
                var gi: usize = 0;
                while (gi + 2 <= gbytes.len) : (gi += 2) {
                    const v = std.mem.readInt(u16, gbytes[gi..][0..2], .big);
                    if (isGrease(v)) continue;
                    if (info.curve_count < info.curves.len) {
                        info.curves[info.curve_count] = v;
                        info.curve_count += 1;
                    }
                }
            },
            11 => {
                if (edata.len >= 1) {
                    const n = edata[0];
                    for (edata[1..][0..@min(@as(usize, n), edata.len - 1)]) |f| {
                        if (info.point_format_count < info.point_formats.len) {
                            info.point_formats[info.point_format_count] = f;
                            info.point_format_count += 1;
                        }
                    }
                }
            },
            13 => {
                var sr = Reader{ .b = edata };
                const slen = sr.u16v() orelse continue;
                const sbytes = sr.take(slen) orelse continue;
                var si: usize = 0;
                while (si + 2 <= sbytes.len) : (si += 2) {
                    const v = std.mem.readInt(u16, sbytes[si..][0..2], .big);
                    if (info.sigalg_count < info.sigalgs.len) {
                        info.sigalgs[info.sigalg_count] = v;
                        info.sigalg_count += 1;
                    }
                }
            },
            16 => {
                var ar = Reader{ .b = edata };
                const alen = ar.u16v() orelse continue;
                const abytes = ar.take(alen) orelse continue;
                var ai: usize = 0;
                var first = true;
                while (ai < abytes.len) {
                    const plen = abytes[ai];
                    ai += 1;
                    if (ai + plen > abytes.len) break;
                    const proto = abytes[ai..][0..plen];
                    if (proto.len > 0) {
                        if (first) {
                            info.alpn_first_char = proto[0];
                            first = false;
                        }
                        info.alpn_last_char = proto[proto.len - 1];
                    }
                    ai += plen;
                }
            },
            43 => {
                if (edata.len >= 1) {
                    const n = edata[0];
                    const vbytes = edata[1..][0..@min(@as(usize, n), edata.len - 1)];
                    var vi: usize = 0;
                    while (vi + 2 <= vbytes.len) : (vi += 2) {
                        const v = std.mem.readInt(u16, vbytes[vi..][0..2], .big);
                        if (isGrease(v)) continue;
                        if (info.supported_version_count < info.supported_versions.len) {
                            info.supported_versions[info.supported_version_count] = v;
                            info.supported_version_count += 1;
                        }
                    }
                }
            },
            else => {},
        }
    }
    return info;
}

fn appendDec(list: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, v: u32) !void {
    var tmp: [16]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{v});
    try list.appendSlice(alloc, s);
}

fn joinDecU16(list: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, vals: []const u16, sep: u8) !void {
    for (vals, 0..) |v, i| {
        if (i > 0) try list.append(alloc, sep);
        try appendDec(list, alloc, v);
    }
}

fn buildJa3String(alloc: std.mem.Allocator, info: *const HelloInfo) ![]u8 {
    var list = std.ArrayListUnmanaged(u8).empty;
    errdefer list.deinit(alloc);
    try appendDec(&list, alloc, info.legacy_version);
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.ciphers[0..info.cipher_count], '-');
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.extensions[0..info.extension_count], '-');
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.curves[0..info.curve_count], '-');
    try list.append(alloc, ',');
    for (info.point_formats[0..info.point_format_count], 0..) |f, i| {
        if (i > 0) try list.append(alloc, '-');
        try appendDec(&list, alloc, f);
    }
    return list.toOwnedSlice(alloc);
}

fn hex4(buf: *[4]u8, v: u16) []const u8 {
    return std.fmt.bufPrint(buf, "{x:0>4}", .{v}) catch unreachable;
}

fn buildJa4(alloc: std.mem.Allocator, info: *const HelloInfo) ![]u8 {
    // Version: highest supported_versions entry wins, else legacy.
    var ver: u16 = info.legacy_version;
    for (info.supported_versions[0..info.supported_version_count]) |v| {
        if (v > ver) ver = v;
    }
    const ver_code: []const u8 = switch (ver) {
        0x0304 => "13",
        0x0303 => "12",
        0x0302 => "11",
        0x0301 => "10",
        else => "00",
    };
    // Cipher hash: sha256 over the sorted cipher ids, lowercase 4-hex,
    // comma-joined; first 12 hex chars of the digest.
    var sorted_ciphers: [128]u16 = undefined;
    @memcpy(sorted_ciphers[0..info.cipher_count], info.ciphers[0..info.cipher_count]);
    const cs = sorted_ciphers[0..info.cipher_count];
    std.mem.sort(u16, cs, {}, std.sort.asc(u16));
    var cipher_input = std.ArrayListUnmanaged(u8).empty;
    defer cipher_input.deinit(alloc);
    for (cs, 0..) |v, i| {
        if (i > 0) try cipher_input.append(alloc, ',');
        var b: [4]u8 = undefined;
        try cipher_input.appendSlice(alloc, hex4(&b, v));
    }
    var cipher_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cipher_input.items, &cipher_hash, .{});
    const cipher_hex = std.fmt.bytesToHex(cipher_hash, .lower);
    const cipher_part: []const u8 = if (info.cipher_count == 0) "000000000000" else cipher_hex[0..12];

    // Extension hash: sorted extension ids excluding SNI (0) and ALPN
    // (16), then "_" + signature algorithms in wire order.
    var exts: [128]u16 = undefined;
    var ext_n: usize = 0;
    for (info.extensions[0..info.extension_count]) |e| {
        if (e == 0 or e == 16) continue;
        exts[ext_n] = e;
        ext_n += 1;
    }
    const es = exts[0..ext_n];
    std.mem.sort(u16, es, {}, std.sort.asc(u16));
    var ext_input = std.ArrayListUnmanaged(u8).empty;
    defer ext_input.deinit(alloc);
    for (es, 0..) |v, i| {
        if (i > 0) try ext_input.append(alloc, ',');
        var b: [4]u8 = undefined;
        try ext_input.appendSlice(alloc, hex4(&b, v));
    }
    if (info.sigalg_count > 0) {
        try ext_input.append(alloc, '_');
        for (info.sigalgs[0..info.sigalg_count], 0..) |v, i| {
            if (i > 0) try ext_input.append(alloc, ',');
            var b: [4]u8 = undefined;
            try ext_input.appendSlice(alloc, hex4(&b, v));
        }
    }
    var ext_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(ext_input.items, &ext_hash, .{});
    const ext_hex = std.fmt.bytesToHex(ext_hash, .lower);
    const ext_part: []const u8 = if (ext_n == 0 and info.sigalg_count == 0) "000000000000" else ext_hex[0..12];

    const cc: u32 = @intCast(@min(info.cipher_count, 99));
    const ec: u32 = @intCast(@min(info.extension_count, 99));
    const a: u8 = if (info.alpn_first_char != 0) info.alpn_first_char else '0';
    const l: u8 = if (info.alpn_last_char != 0) info.alpn_last_char else '0';
    return std.fmt.allocPrint(alloc, "t{s}{s}{d:0>2}{d:0>2}{c}{c}_{s}_{s}", .{
        ver_code,
        if (info.has_sni) "d" else "i",
        cc,
        ec,
        a,
        l,
        cipher_part,
        ext_part,
    });
}

fn helloInfoFor(handle: u64) ?HelloInfo {
    const h = handleFromU64(handle) orelse return null;
    if (h.hello_len == 0) return null;
    return parseHello(h.hello_buf[0..h.hello_len]);
}

pub export fn sa_std_tls_shaped_hello_ja3_string(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa3String(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    return writeOut(out, out_cap, out_len, s);
}

pub export fn sa_std_tls_shaped_hello_ja3(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa3String(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    var digest: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(s, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return writeOut(out, out_cap, out_len, &hex);
}

pub export fn sa_std_tls_shaped_hello_ja4(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa4(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    return writeOut(out, out_cap, out_len, s);
}

// ============================================================================
// Unit tests.
// ============================================================================

const testing = std.testing;

fn sslAvailable() bool {
    var flag: u32 = 0;
    if (sa_std_tls_shaped_supported(&flag) != SA_STD_OK) return false;
    return flag == 1;
}

test "supported reports the dlopen result and validates the slot" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_supported(&flag));
    try testing.expect(flag == 0 or flag == 1);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_supported(null));
}

test "profile validation rejects bad documents before any dial" {
    if (!sslAvailable()) return;
    const host = "127.0.0.1";
    var h: u64 = 0;
    // unknown key
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"bogus\":1}".ptr, 11, &h));
    // grease is honestly unsupported on the OpenSSL backend
    try testing.expectEqual(@as(i32, SA_STD_ERR_UNSUPPORTED), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"grease\":true}".ptr, 16, &h));
    // unknown preset
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"preset\":\"netscape\"}".ptr, 21, &h));
    // unknown version
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"min_version\":\"1.9\"}".ptr, 22, &h));
    // malformed JSON
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{oops".ptr, 5, &h));
    // valid empty profile, dead port -> dial error, handle stays 0
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{}".ptr, 2, &h));
    try testing.expectEqual(@as(u64, 0), h);
    // bad host/port arguments
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 0, null, 0, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(null, 0, 443, null, 0, &h));
}

fn makeCert(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, "cert.pem" });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, "key.pem" });
    errdefer allocator.free(key_path);
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "1", "-nodes", "-subj", "/CN=localhost",
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

fn freePort() !u16 {
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    return switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
}

fn spawnServer(allocator: std.mem.Allocator, cert: []const u8, key: []const u8, port: u16, extra: []const []const u8) !sio.Child {
    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    var args = std.ArrayListUnmanaged([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "openssl", "s_server", "-accept", accept_arg, "-cert", cert, "-key", key, "-quiet" });
    try args.appendSlice(allocator, extra);
    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    return child;
}

fn connectRetry(port: u16, profile: []const u8) i64 {
    const host = "localhost";
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_shaped_connect(host.ptr, host.len, port, profile.ptr, profile.len, &handle);
        if (rc == SA_STD_OK) return @intCast(handle);
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

fn negotiatedJson(handle: u64, buf: []u8) ![]const u8 {
    var jh: u64 = 0;
    if (sa_std_tls_shaped_negotiated_json(handle, &jh) != SA_STD_OK) return error.NegotiatedFailed;
    defer _ = sa_std_tls_shaped_buffer_free(jh);
    const ptr = sa_std_tls_shaped_buffer_data(jh) orelse return error.MissingData;
    const len = sa_std_tls_shaped_buffer_len(jh);
    const n = @min(@as(usize, @intCast(len)), buf.len);
    @memcpy(buf[0..n], ptr[0..n]);
    return buf[0..n];
}

fn testDirSetup(allocator: std.mem.Allocator) !struct { td: testing.TmpDir, dirpath: []u8, cert: []u8, key: []u8 } {
    var td = testing.tmpDir(.{});
    errdefer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    errdefer allocator.free(dirpath);
    const paths = try makeCert(allocator, dirpath);
    return .{ .td = td, .dirpath = dirpath, .cert = paths.cert, .key = paths.key };
}

test "loopback: chrome preset handshake, echo, negotiated + ja3/ja4 from captured hello" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
    const profile = try std.fmt.allocPrint(allocator, "{{\"preset\":\"chrome\",\"ca_file\":\"{s}\"}}", .{setup.cert});
    defer allocator.free(profile);

    const rc = connectRetry(port, profile);
    try testing.expect(rc > 0);
    const handle: u64 = @intCast(rc);
    defer _ = sa_std_tls_shaped_close(handle);

    // negotiated values
    var jbuf: [512]u8 = undefined;
    const json = try negotiatedJson(handle, &jbuf);
    try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"TLSv1.3\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"alpn\":\"\"") != null);

    // JA3 computed from the captured ClientHello: TLS1.3 suites lead.
    var ja3s_buf: [2048]u8 = undefined;
    var ja3s_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(handle, &ja3s_buf, ja3s_buf.len, &ja3s_len));
    const ja3s = ja3s_buf[0..@intCast(ja3s_len)];
    try testing.expect(std.mem.startsWith(u8, ja3s, "771,"));
    try testing.expect(std.mem.indexOf(u8, ja3s, "4865-4866-4867") != null);
    var ja3_buf: [64]u8 = undefined;
    var ja3_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3(handle, &ja3_buf, ja3_buf.len, &ja3_len));
    try testing.expectEqual(@as(u64, 32), ja3_len);
    var ja4_buf: [128]u8 = undefined;
    var ja4_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja4(handle, &ja4_buf, ja4_buf.len, &ja4_len));
    const ja4 = ja4_buf[0..@intCast(ja4_len)];
    try testing.expect(std.mem.startsWith(u8, ja4, "t13d"));
    try testing.expectEqual(@as(usize, 33), ja4.len);

    // echo: server stdin -> TLS -> us; our write -> server stdout
    const msg = "shaped-hello\n";
    try server.stdin.?.writeAll(msg);
    var got: [64]u8 = undefined;
    var total: usize = 0;
    while (total < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, got[total..].ptr, got.len - total, &n));
        if (n == 0) break;
        total += @intCast(n);
    }
    try testing.expectEqualStrings(msg, got[0..total]);
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, "ping-back".ptr, 9, &written));
    try testing.expectEqual(@as(u64, 9), written);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_close(handle));

    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    const term = try server.wait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
    try testing.expect(std.mem.indexOf(u8, echoed, "ping-back") != null);
}

test "loopback: ciphersuite restriction, alpn selection, version cap, ja3 order sensitivity" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    // --- restricted TLS1.3 suite + ciphersuite order changes the JA3 ---
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "2", "-alpn", "h2" });
        defer _ = server.kill() catch {};

        const p1 = try std.fmt.allocPrint(allocator, "{{\"ca_file\":\"{s}\",\"ciphersuites\":\"TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256\",\"alpn\":[\"h2\"]}}", .{setup.cert});
        defer allocator.free(p1);
        const rc1 = connectRetry(port, p1);
        try testing.expect(rc1 > 0);
        const h1: u64 = @intCast(rc1);
        var jbuf: [512]u8 = undefined;
        const json = try negotiatedJson(h1, &jbuf);
        try testing.expect(std.mem.indexOf(u8, json, "\"cipher\":\"TLS_AES_256_GCM_SHA384\"") != null);
        try testing.expect(std.mem.indexOf(u8, json, "\"alpn\":\"h2\"") != null);
        var s1: [2048]u8 = undefined;
        var l1: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(h1, &s1, s1.len, &l1));
        try testing.expect(std.mem.indexOf(u8, s1[0..@intCast(l1)], "4866-4865") != null);
        _ = sa_std_tls_shaped_close(h1);

        const p2 = try std.fmt.allocPrint(allocator, "{{\"ca_file\":\"{s}\",\"ciphersuites\":\"TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384\",\"alpn\":[\"h2\"]}}", .{setup.cert});
        defer allocator.free(p2);
        const rc2 = connectRetry(port, p2);
        try testing.expect(rc2 > 0);
        const h2: u64 = @intCast(rc2);
        var s2: [2048]u8 = undefined;
        var l2: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(h2, &s2, s2.len, &l2));
        try testing.expect(std.mem.indexOf(u8, s2[0..@intCast(l2)], "4865-4866") != null);
        try testing.expect(!std.mem.eql(u8, s1[0..@intCast(l1)], s2[0..@intCast(l2)]));
        _ = sa_std_tls_shaped_close(h2);
        _ = try server.wait();
    }

    // --- max_version 1.2 negotiates TLS 1.2 with an ECDHE suite ---
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const profile = try std.fmt.allocPrint(allocator, "{{\"preset\":\"chrome\",\"ca_file\":\"{s}\",\"max_version\":\"1.2\"}}", .{setup.cert});
        defer allocator.free(profile);
        const rc = connectRetry(port, profile);
        try testing.expect(rc > 0);
        const handle: u64 = @intCast(rc);
        var jbuf: [512]u8 = undefined;
        const json = try negotiatedJson(handle, &jbuf);
        try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"TLSv1.2\"") != null);
        try testing.expect(std.mem.indexOf(u8, json, "ECDHE") != null);
        _ = sa_std_tls_shaped_close(handle);
        _ = try server.wait();
    }
}

// ---- profile configuration additions (loopback only) ---------------------------

fn profileJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn connectRetryProfile(host: []const u8, port: u16, profile: []const u8) i64 {
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_shaped_connect(host.ptr, host.len, port, profile.ptr, profile.len, &handle);
        if (rc == SA_STD_OK) return @intCast(handle);
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

fn shapedEcho(handle: u64, msg: []const u8) !void {
    // Only for peers that echo at the TLS level (our own tls_server test
    // runner). s_server does NOT echo; see shapedServerRoundTrip.
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, msg.ptr, msg.len, &written));
    try testing.expectEqual(@as(u64, msg.len), written);
    var buf: [128]u8 = undefined;
    var got: usize = 0;
    while (got < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, buf[got..].ptr, buf.len - got, &n));
        if (n == 0) break;
        got += @intCast(n);
    }
    try testing.expectEqualStrings(msg, buf[0..got]);
}

/// s_server round trip, mirroring the pre-existing shaped tests: server
/// stdin is sent to us over TLS; what we write shows up on server stdout.
fn shapedServerRoundTrip(allocator: std.mem.Allocator, server: *sio.Child, handle: u64) !void {
    const msg = "server-to-shaped\n";
    try server.stdin.?.writeAll(msg);
    var got: [64]u8 = undefined;
    var total: usize = 0;
    while (total < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, got[total..].ptr, got.len - total, &n));
        if (n == 0) break;
        total += @intCast(n);
    }
    try testing.expectEqualStrings(msg, got[0..total]);
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, "shaped-to-server".ptr, 16, &written));
    try testing.expectEqual(@as(u64, 16), written);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_close(handle));
    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    try testing.expect(std.mem.indexOf(u8, echoed, "shaped-to-server") != null);
}

test "profile validation: session blob and key conflicts are rejected before dialing" {
    if (!sslAvailable()) return;
    // Nothing listens on port 1; a profile error must surface as
    // INVALID_ARGUMENT before any connection attempt (an IO error here
    // would mean validation ran after dialing).
    const bad_session = "{\"session\":\"!!!not-base64!!!\"}";
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, bad_session.ptr, bad_session.len, &h));
    const both_ca = "{\"ca_file\":\"/tmp/x.pem\",\"ca_pem\":\"y\"}";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, both_ca.ptr, both_ca.len, &h));
    const half_cert = "{\"cert_file\":\"/tmp/x.pem\"}";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, half_cert.ptr, half_cert.len, &h));
}

test "loopback: ca_pem + sni override verifies by IP; wrong CA fails; insecure is explicit" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    // A second, unrelated cert serves as the "wrong CA".
    var td2 = testing.tmpDir(.{});
    defer td2.cleanup();
    const tdir2 = sio.Dir{ .inner = td2.dir };
    const dirpath2 = try tdir2.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath2);
    const other = try makeCert(allocator, dirpath2);
    defer allocator.free(other.cert);
    defer allocator.free(other.key);
    const other_pem = try sio.readFileAbsoluteAlloc(allocator, other.cert, 1 << 20);
    defer allocator.free(other_pem);

    // (1) ca_pem pins trust, sni names the peer: dial by IP, verify as
    // "localhost".
    {
        const profile = try profileJson(allocator, .{ .sni = "localhost", .ca_pem = pem });
        defer allocator.free(profile);
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const h = connectRetryProfile("127.0.0.1", port, profile);
        try testing.expect(h > 0);
        try shapedServerRoundTrip(allocator, &server, @intCast(h));
        _ = server.wait() catch {};
    }
    // (2) Wrong CA in ca_pem: explicit verification failure, no fallback.
    {
        const profile = try profileJson(allocator, .{ .sni = "localhost", .ca_pem = other_pem });
        defer allocator.free(profile);
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        try testing.expectEqual(@as(i64, SA_STD_ERR_TLS_VERIFY), connectRetryProfile("127.0.0.1", port, profile));
        _ = server.wait() catch {};
    }
    // (3) Default profile (full verification, system store): the
    // self-signed peer fails.
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        try testing.expectEqual(@as(i64, SA_STD_ERR_TLS_VERIFY), connectRetryProfile("127.0.0.1", port, "{}"));
        _ = server.wait() catch {};
    }
    // (4) The explicitly named insecure switch connects.
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const h = connectRetryProfile("127.0.0.1", port, "{\"insecure_skip_verify\":true}");
        try testing.expect(h > 0);
        _ = sa_std_tls_shaped_close(@intCast(h));
        _ = server.wait() catch {};
    }
}

test "loopback: peer_cert_chain_json fields match openssl x509 output" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    const profile = try profileJson(allocator, .{ .ca_pem = pem });
    defer allocator.free(profile);
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
    defer _ = server.kill() catch {};
    const h = connectRetryProfile("localhost", port, profile);
    try testing.expect(h > 0);
    const handle: u64 = @intCast(h);

    var jh: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_peer_cert_chain_json(handle, &jh));
    defer _ = sa_std_tls_shaped_buffer_free(jh);
    const jptr = sa_std_tls_shaped_buffer_data(jh) orelse return error.MissingData;
    const jlen = sa_std_tls_shaped_buffer_len(jh);
    const json = jptr[0..@intCast(jlen)];

    try testing.expect(std.mem.indexOf(u8, json, "\"common_name\":\"localhost\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"subject\":\"CN = localhost\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"not_before\":") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"not_after\":") != null);

    // Cross-check serial + SHA-256 fingerprint against the openssl CLI.
    const fp = try opensslX509Field(allocator, setup.cert, "-fingerprint");
    defer allocator.free(fp);
    try testing.expect(std.mem.indexOf(u8, json, fp) != null);
    const serial = try opensslX509Field(allocator, setup.cert, "-serial");
    defer allocator.free(serial);
    // serial_hex is the bare hex; openssl prints it after '='.
    try testing.expect(std.mem.indexOf(u8, json, serial) != null);
    _ = sa_std_tls_shaped_close(handle);
    _ = server.wait() catch {};
}

fn opensslX509Field(allocator: std.mem.Allocator, cert: []const u8, flag: []const u8) ![]u8 {
    const args: []const []const u8 = if (std.mem.eql(u8, flag, "-fingerprint"))
        &.{ "openssl", "x509", "-in", cert, "-noout", flag, "-sha256" }
    else
        &.{ "openssl", "x509", "-in", cert, "-noout", flag };
    var child = sio.Child.init(args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(out);
    const term = try child.wait();
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslX509Failed,
        else => return error.OpensslX509Failed,
    }
    const eq = std.mem.indexOfScalar(u8, out, '=') orelse return error.OpensslX509Failed;
    return allocator.dupe(u8, std.mem.trim(u8, out[eq + 1 ..], " \t\r\n"));
}

test "loopback: TLS 1.2 session blob resumes (session_reused=true)" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    const profile1 = try profileJson(allocator, .{ .max_version = "1.2", .ca_file = setup.cert });
    defer allocator.free(profile1);
    var blob: []u8 = undefined;
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const h = connectRetryProfile("localhost", port, profile1);
        try testing.expect(h > 0);
        const handle: u64 = @intCast(h);
        var bh: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_session_blob(handle, &bh));
        defer _ = sa_std_tls_shaped_buffer_free(bh);
        const bptr = sa_std_tls_shaped_buffer_data(bh) orelse return error.MissingData;
        const blen = sa_std_tls_shaped_buffer_len(bh);
        try testing.expect(blen > 0);
        blob = try allocator.dupe(u8, bptr[0..@intCast(blen)]);
        _ = sa_std_tls_shaped_close(handle);
        _ = server.wait() catch {};
    }
    defer allocator.free(blob);

    const profile2 = try profileJson(allocator, .{ .max_version = "1.2", .ca_file = setup.cert, .session = blob });
    defer allocator.free(profile2);
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
    defer _ = server.kill() catch {};
    const h = connectRetryProfile("localhost", port, profile2);
    try testing.expect(h > 0);
    const handle: u64 = @intCast(h);
    var nbuf: [256]u8 = undefined;
    const negotiated = try negotiatedJson(handle, &nbuf);
    try testing.expect(std.mem.indexOf(u8, negotiated, "\"session_reused\":true") != null);
    _ = sa_std_tls_shaped_close(handle);
    _ = server.wait() catch {};
}

test "start_tls: shaped upgrade after plaintext preamble" {
    if (!sslAvailable()) return;
    if (comptime builtin.os.tag == .windows) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    const srv = @import("sa_tls_server.zig");
    var sup: u32 = 0;
    _ = srv.sa_std_tls_server_supported(&sup);
    if (sup == 0) return;
    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), srv.sa_std_tls_server_ctx_create(setup.cert.ptr, setup.cert.len, setup.key.ptr, setup.key.len, &ctx));
    defer _ = srv.sa_std_tls_server_ctx_free(ctx);

    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    const Arg = struct { ctx: u64, lst: *std.Io.net.Server, accept_rc: i32 = -999 };
    var arg: Arg = .{ .ctx = ctx, .lst = &listener };
    const Runner = struct {
        fn run(a: *Arg) void {
            const s = @import("sa_tls_server.zig");
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
            var line_buf: [16]u8 = undefined;
            var line_len: usize = 0;
            while (line_len < line_buf.len) {
                var b: [1]u8 = undefined;
                const n = std.posix.read(stream.socket.handle, &b) catch return;
                if (n == 0) return;
                line_buf[line_len] = b[0];
                line_len += 1;
                if (b[0] == '\n') break;
            }
            if (!std.mem.eql(u8, line_buf[0..line_len], "STARTTLS\n")) return;
            var ssl: u64 = 0;
            a.accept_rc = s.sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
            if (a.accept_rc != 0) return;
            var buf: [64]u8 = undefined;
            var n: u64 = 0;
            if (s.sa_std_tls_server_read(ssl, &buf, buf.len, &n) == 0) {
                _ = s.sa_std_tls_server_write(ssl, &buf, n, &n);
            }
            _ = s.sa_std_tls_server_close(ssl);
        }
    };
    var thread = try std.Thread.spawn(.{}, Runner.run, .{&arg});

    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var plain = try addr.connect(sio.io(), .{ .mode = .stream });
    var wb: [64]u8 = undefined;
    var wr = plain.writer(sio.io(), &wb);
    try wr.interface.writeAll("STARTTLS\n");
    try wr.interface.flush();

    const profile = try profileJson(allocator, .{ .ca_pem = pem });
    defer allocator.free(profile);
    const host = "localhost";
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_start_tls(plain.socket.handle, host.ptr, host.len, profile.ptr, profile.len, &handle));
    try testing.expect(handle != 0);
    try shapedEcho(handle, "shaped-starttls-echo");
    _ = sa_std_tls_shaped_close(handle);
    thread.join();
    try testing.expectEqual(@as(i32, 0), arg.accept_rc);
}

test "loopback: client certificate (cert_file/key_file) satisfies a verifying server" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    // Server demands a client cert chaining to the same self-signed cert
    // used as its CA file; the client presents that very cert.
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1", "-Verify", "1", "-verify_return_error", "-CAfile", setup.cert });
    defer _ = server.kill() catch {};
    const profile = try profileJson(allocator, .{ .ca_pem = pem, .cert_file = setup.cert, .key_file = setup.key });
    defer allocator.free(profile);
    const h = connectRetryProfile("localhost", port, profile);
    try testing.expect(h > 0);
    _ = sa_std_tls_shaped_close(@intCast(h));
    _ = server.wait() catch {};

    // Without the client certificate the same server refuses us.
    const port2 = try freePort();
    var server2 = try spawnServer(allocator, setup.cert, setup.key, port2, &.{ "-naccept", "1", "-Verify", "1", "-verify_return_error", "-CAfile", setup.cert });
    defer _ = server2.kill() catch {};
    const profile2 = try profileJson(allocator, .{ .ca_pem = pem });
    defer allocator.free(profile2);
    const rc = connectRetryProfile("localhost", port2, profile2);
    try testing.expect(rc < 0);
    _ = server2.wait() catch {};
}
