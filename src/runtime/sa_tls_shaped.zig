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
// Trust model matches sa_tls_client.zig: verification is always on
// (system trust store via SSL_CTX_set_default_verify_paths, or the
// profile's ca_file), hostname is checked (SSL_set1_host), and
// SSL_get_verify_result must be X509_V_OK after the handshake. There is
// deliberately no verification-disabled path.
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
};

var ssl_api: ?SslApi = null;
var ssl_api_mutex = std.Io.Mutex.init;

fn loadSslApi() ?*SslApi {
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
        .get_alpn_selected = l.lookup(*const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void, "SSL_get_alpn_selected") orelse return null,
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

fn doConnect(api: *SslApi, host_slice: []const u8, port: u16, eff: *const Effective) ConnectError!*ShapedHandle {
    const alloc = std.heap.page_allocator;

    const stream = dialHost(host_slice, port) catch return ConnectError.Io;
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
    if (eff.min_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }
    if (eff.max_version) |v| {
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, versionConst(v).?, null) != 1) return ConnectError.InvalidArgument;
    }

    // Verification: always on. System store by default; ca_file replaces
    // it with an explicit private CA (loopback tests, private PKI).
    if (eff.ca_file) |v| {
        const z = toZ(alloc, v) orelse return ConnectError.OutOfMemory;
        defer alloc.free(z);
        if (api.ctx_load_verify_locations(ctx, z.ptr, null) != 1) return ConnectError.Io;
    } else {
        if (api.ctx_set_default_verify_paths(ctx) != 1) return ConnectError.Io;
    }
    api.ctx_set_verify(ctx, SSL_VERIFY_PEER, null);

    const ssl = api.new(ctx) orelse return ConnectError.Io;
    errdefer api.free(ssl);

    const host_z = toZ(alloc, host_slice) orelse return ConnectError.OutOfMemory;
    defer alloc.free(host_z);
    if (api.set1_host(ssl, host_z.ptr) != 1) return ConnectError.InvalidArgument;
    _ = api.ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, @ptrCast(@constCast(host_z.ptr)));

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
        const vrc = api.get_verify_result(ssl);
        return if (vrc != 0) ConnectError.TlsVerify else ConnectError.Io;
    }
    if (api.get_verify_result(ssl) != 0) return ConnectError.TlsVerify;
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
    var buffer: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"version\":\"{s}\",\"cipher\":\"{s}\",\"alpn\":\"{s}\"}}", .{ version, cipher, alpn }) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
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
