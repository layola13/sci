// TLS client with ClientHello fingerprint shaping for the sci/sa_std
test "sa_tls_shaped_tests" { std.testing.refAllDecls(@import("sa_tls_shaped_test.zig")); }
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
pub const builtin = @import("builtin");
pub const sio = @import("sio");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_NO_MEMORY: i32 = -12;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
pub const SA_STD_ERR_UNSUPPORTED: i32 = -1;
pub const SA_STD_ERR_IO: i32 = -5;
pub const SA_STD_ERR_TLS_VERIFY: i32 = -100;

pub fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

// ---- OpenSSL dlopen surface ------------------------------------------------

pub const SslCtx = opaque {};
pub const Ssl = opaque {};
pub const SslMethod = opaque {};
pub const SslCipher = opaque {};
pub const Bio = opaque {};
pub const X509 = opaque {};
pub const X509Store = opaque {};
pub const X509Name = opaque {};
pub const SslStack = opaque {};
pub const SslSession = opaque {};

pub const MsgCallback = *const fn (write_p: c_int, version: c_int, content_type: c_int, buf: ?*const anyopaque, len: usize, ssl: ?*Ssl, arg: ?*anyopaque) callconv(.c) void;

pub const SslApi = struct {
    lib: std.DynLib,
    method_new: *const fn () callconv(.c) ?*const SslMethod,
    ctx_new: *const fn (?*const SslMethod) callconv(.c) ?*SslCtx,
    ctx_free: *const fn (?*SslCtx) callconv(.c) void,
    ctx_set_ciphersuites: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    ctx_set_cipher_list: *const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int,
    // (groups/sigalgs list setters are ctrl macros -- no fields)
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
    // (msg-callback-arg setter is a ctrl macro -- no field)
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
    x509_name_print_ex: *const fn (?*Bio, ?*const X509Name, c_int, c_ulong) callconv(.c) c_int,
    bio_s_mem: *const fn () callconv(.c) ?*anyopaque,
    bio_new: *const fn (?*anyopaque) callconv(.c) ?*Bio,
    bio_read: *const fn (?*Bio, [*]u8, c_int) callconv(.c) c_int,
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

pub var ssl_api: ?SslApi = null;
pub var ssl_api_mutex = std.Io.Mutex.init;

pub fn loadSslApi() ?*SslApi {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadSslApiNative();
    }
}

pub const loadSslApiNative = @import("sa_tls_shaped_ssl.zig").loadSslApiNative;

// SSL_CTRL_SET_TLSEXT_HOSTNAME / TLSEXT_NAMETYPE_host_name
pub const SSL_CTRL_SET_TLSEXT_HOSTNAME: c_int = 55;
// openssl/ssl.h macro bodies (the *_list / *_arg setters):
pub const SSL_CTRL_SET_MSG_CALLBACK_ARG: c_int = 16;
pub const SSL_CTRL_SET_GROUPS_LIST: c_int = 92;
pub const SSL_CTRL_SET_SIGALGS_LIST: c_int = 98;
// SSL_CTX ctrl ids for proto version bounds
pub const SSL_CTRL_SET_MIN_PROTO_VERSION: c_int = 123;
pub const SSL_CTRL_SET_MAX_PROTO_VERSION: c_int = 124;
pub const SSL_VERIFY_PEER: c_int = 0x01;
pub const SSL_FILETYPE_PEM: c_int = 1;
const SSL_ERROR_ZERO_RETURN: c_int = 6;

// ---- profiles ---------------------------------------------------------------

pub const Profile = @import("sa_tls_shaped_profile.zig").Profile;

pub const Effective = @import("sa_tls_shaped_profile.zig").Effective;

pub const TLS13_SUITES = @import("sa_tls_shaped_profile.zig").TLS13_SUITES;
pub const BROWSER_SIGALGS = @import("sa_tls_shaped_profile.zig").BROWSER_SIGALGS;

pub const presetEffective = @import("sa_tls_shaped_profile.zig").presetEffective;

pub const versionConst = @import("sa_tls_shaped_profile.zig").versionConst;

// Merge a parsed profile over its preset and validate it. The returned
// Effective borrows strings from `p` (and static preset literals), so the
// caller must keep the parsed document alive while applying it.
pub const ResolveResult = @import("sa_tls_shaped_profile.zig").ResolveResult;

pub const effectiveFromProfile = @import("sa_tls_shaped_profile.zig").effectiveFromProfile;

// ---- connection handle ------------------------------------------------------

pub const hello_cap = 65536;

pub const ShapedHandle = struct {
    ssl: *Ssl,
    ctx: *SslCtx,
    stream: std.Io.net.Stream,
    host: []u8,
    hello_buf: []u8,
    hello_len: usize = 0,
    hello_truncated: bool = false,
};

pub fn msgCallback(write_p: c_int, version: c_int, content_type: c_int, buf: ?*const anyopaque, len: usize, ssl: ?*Ssl, arg: ?*anyopaque) callconv(.c) void {
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

pub fn dialHost(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

pub fn toZ(alloc: std.mem.Allocator, s: []const u8) ?[:0]u8 {
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

pub const ConnectError = error{ InvalidArgument, OutOfMemory, TlsVerify, Unsupported, Io };

/// Validate a profile JSON document exactly as connect would
/// (parse + resolve), without dialing. Returns SA_STD_OK for an
/// acceptable profile (including the empty document, which means
/// the default profile) or the same status the connect path
/// would produce for the document. Lets callers that store a
/// profile for later use fail at configuration time instead of
/// at first connect.
pub fn shapedProfileCheck(profile_json: []const u8) i32 {
    if (profile_json.len == 0) return SA_STD_OK;
    var parsed = std.json.parseFromSlice(Profile, std.heap.page_allocator, profile_json, .{ .ignore_unknown_fields = false }) catch {
        return SA_STD_ERR_INVALID_ARGUMENT;
    };
    defer parsed.deinit();
    switch (effectiveFromProfile(&parsed.value)) {
        .ok => |eff| {
            if (eff.session_der) |d| std.heap.page_allocator.free(d);
            return SA_STD_OK;
        },
        .err => |code| return code,
    }
}

/// Load every certificate in a PEM blob into the ctx trust store. Returns
/// false when the blob yields no usable certificate (loud failure at the
/// call site, never a silent empty store).
pub const loadCaPemIntoStore = @import("sa_tls_shaped_connect.zig").loadCaPemIntoStore;

pub const doConnect = @import("sa_tls_shaped_connect.zig").doConnect;

/// Handshake core shared by connect and start_tls: takes ownership of
/// `stream` (the errdefer chain closes it on every failure path).
pub const doConnectOnStream = @import("sa_tls_shaped_connect.zig").doConnectOnStream;

pub const freeHandle = @import("sa_tls_shaped_connect.zig").freeHandle;

pub const handleFromU64 = @import("sa_tls_shaped_connect.zig").handleFromU64;

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

pub const appendJsonEscaped = @import("sa_tls_shaped_cert.zig").appendJsonEscaped;

pub const appendHexUpper = @import("sa_tls_shaped_cert.zig").appendHexUpper;

/// Serial number (INTEGER content bytes, hex) from the certificate DER:
/// outer SEQUENCE -> TBS SEQUENCE -> optional [0] version -> INTEGER.
pub const serialHex = @import("sa_tls_shaped_cert.zig").serialHex;

/// Collect dNSName / iPAddress entries from the parsed SAN extension.
pub const collectSans = @import("sa_tls_shaped_cert.zig").collectSans;

/// Pinned X509_NAME_print_ex flags for the display rendering of
/// certificate names in the peer chain JSON, spelled out bit by bit
/// (values from openssl/asn1.h and openssl/x509.h, OpenSSL 3) so the
/// emitted format is a constant of this code and can never drift with
/// library defaults. This is exactly the XN_FLAG_ONELINE preset the
/// OpenSSL 3 CLI uses for `openssl x509 -subject` / `-issuer`:
///   ASN1_STRFLGS_ESC_2253 0x1 | ESC_CTRL 0x2 | ESC_MSB 0x4 |
///   UTF8_CONVERT 0x10 | DUMP_UNKNOWN 0x100 | DUMP_DER 0x200
///     (= ASN1_STRFLGS_RFC2253: RFC 2253 escaping, unknown fields
///     dumped, never silently dropped),
///   ASN1_STRFLGS_ESC_QUOTE 0x8 (quote values holding separators
///     instead of backslash-escaping them),
///   XN_FLAG_SEP_CPLUS_SPC (2 << 16): ", " between RDNs, " + "
///     inside a multi-valued RDN,
///   XN_FLAG_SPC_EQ (1 << 23): " = " around '=',
///   XN_FLAG_FN_SN (0): short field names, in certificate order.
/// Verified byte-equal to the CLI default output on OpenSSL 3.0.13
/// for subject and issuer of simple, multi-RDN/special-character and
/// UTF-8 names (2026-11-06 flags probe).
pub const X509_NAME_DISPLAY_FLAGS = @import("sa_tls_shaped_cert.zig").X509_NAME_DISPLAY_FLAGS;

pub const appendX509DisplayName = @import("sa_tls_shaped_cert.zig").appendX509DisplayName;

/// JSON document for a peer chain: one entry per certificate, leaf first,
/// with decoded subject/issuer (display form, see below), common name, SAN
/// dNSName/iPAddress lists, validity window (unix seconds), serial (hex)
/// and the SHA-256 fingerprint (openssl colon-hex form). Certificates the
/// std DER parser cannot decode are still listed (names + fingerprint)
/// with "fields_parsed":false -- never silently dropped.
///
/// The subject/issuer strings are a DISPLAY format: the OpenSSL 3 spaced
/// rendering ("CN = localhost") produced by X509_NAME_print_ex with the
/// explicitly pinned flags of X509_NAME_DISPLAY_FLAGS -- never the
/// deprecated X509_NAME_oneline slash form. They are for human readers;
/// consumers must not parse them (common_name and the structured fields
/// are the machine-readable surface).
pub const buildPeerCertChainJson = @import("sa_tls_shaped_cert.zig").buildPeerCertChainJson;

pub const sa_std_tls_shaped_peer_cert_chain_json = @import("sa_tls_shaped_cert.zig").sa_std_tls_shaped_peer_cert_chain_json;

// ---- buffer handle registry (same shape as sa_tls_client.zig) --------------

var string_registry_mutex = std.Io.Mutex.init;
var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

pub fn registerString(bytes: []u8, slot: *u64) i32 {
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

pub const SA_STD_ERR_TRUNCATED: i32 = 9; // matches sa_std.zig's value

pub const writeOut = @import("sa_tls_shaped_ja3.zig").writeOut;

pub const isGrease = @import("sa_tls_shaped_ja3.zig").isGrease;

pub const HelloInfo = @import("sa_tls_shaped_ja3.zig").HelloInfo;

pub const Reader = @import("sa_tls_shaped_ja3.zig").Reader;

pub const parseHello = @import("sa_tls_shaped_ja3.zig").parseHello;

pub const appendDec = @import("sa_tls_shaped_ja3.zig").appendDec;

pub const joinDecU16 = @import("sa_tls_shaped_ja3.zig").joinDecU16;

pub const buildJa3String = @import("sa_tls_shaped_ja3.zig").buildJa3String;

pub const hex4 = @import("sa_tls_shaped_ja3.zig").hex4;

pub const buildJa4 = @import("sa_tls_shaped_ja3.zig").buildJa4;

pub const helloInfoFor = @import("sa_tls_shaped_ja3.zig").helloInfoFor;

pub const sa_std_tls_shaped_hello_ja3_string = @import("sa_tls_shaped_ja3.zig").sa_std_tls_shaped_hello_ja3_string;

pub const sa_std_tls_shaped_hello_ja3 = @import("sa_tls_shaped_ja3.zig").sa_std_tls_shaped_hello_ja3;

pub const sa_std_tls_shaped_hello_ja4 = @import("sa_tls_shaped_ja3.zig").sa_std_tls_shaped_hello_ja4;

// ============================================================================
// Unit tests.
// ============================================================================

pub const testing = std.testing;

pub const sslAvailable = @import("sa_tls_shaped_test.zig").sslAvailable;



pub const makeCert = @import("sa_tls_shaped_test.zig").makeCert;

pub const freePort = @import("sa_tls_shaped_test.zig").freePort;

pub const spawnServer = @import("sa_tls_shaped_test.zig").spawnServer;

pub const connectRetry = @import("sa_tls_shaped_test.zig").connectRetry;

pub const negotiatedJson = @import("sa_tls_shaped_test.zig").negotiatedJson;

pub const testDirSetup = @import("sa_tls_shaped_test.zig").testDirSetup;



// ---- profile configuration additions (loopback only) ---------------------------

pub const profileJson = @import("sa_tls_shaped_test.zig").profileJson;

pub const connectRetryProfile = @import("sa_tls_shaped_test.zig").connectRetryProfile;

pub const shapedEcho = @import("sa_tls_shaped_test.zig").shapedEcho;

/// s_server round trip, mirroring the pre-existing shaped tests: server
/// stdin is sent to us over TLS; what we write shows up on server stdout.
pub const shapedServerRoundTrip = @import("sa_tls_shaped_test.zig").shapedServerRoundTrip;




pub const opensslX509Field = @import("sa_tls_shaped_test.zig").opensslX509Field;



