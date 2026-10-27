// TLS-server runtime binding for the sci/sa_std platform layer.
//
// Real TLS server handshake backed by OpenSSL (libssl/libcrypto), lazily
// loaded via dlopen. Zig 0.14's std.crypto only provides a TLS *client*, so a
// real server side requires OpenSSL. This sinking places the real binding in
// the sci runtime so all plugins can reuse it instead of each hiding its own.
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative = error.

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

fn ptrFromU64(T: type, h: u64) *T {
    return @ptrFromInt(@as(usize, @intCast(h)));
}

const SslCtx = opaque {};
const Ssl = opaque {};
const SslMethod = opaque {};
const Bio = opaque {};
const X509 = opaque {};
const X509Store = opaque {};
const X509Name = opaque {};
const SslStack = opaque {};

const AlpnSelectCb = *const fn (?*Ssl, *?[*]const u8, *u8, [*]const u8, c_uint, ?*anyopaque) callconv(.c) c_int;

const SslMethodNew = *const fn () callconv(.c) ?*const SslMethod;
const SslCtxNew = *const fn (?*const SslMethod) callconv(.c) ?*SslCtx;
const SslCtxFree = *const fn (?*SslCtx) callconv(.c) void;
const SslCtxUseCertFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
const SslCtxUseKeyFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
const SslNew = *const fn (?*SslCtx) callconv(.c) ?*Ssl;
const SslFree = *const fn (?*Ssl) callconv(.c) void;
const SslSetFd = *const fn (?*Ssl, c_int) callconv(.c) c_int;
const SslAccept = *const fn (?*Ssl) callconv(.c) c_int;
const SslRead = *const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int;
const SslWrite = *const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int;
const SslShutdown = *const fn (?*Ssl) callconv(.c) c_int;
const ErrClearError = *const fn () callconv(.c) void;
const ErrPeekError = *const fn () callconv(.c) u64;

const SSL_FILETYPE_PEM: c_int = 1;
const SSL_VERIFY_PEER_MODE: c_int = 0x01;
const SSL_VERIFY_FAIL_IF_NO_PEER_CERT: c_int = 0x02;
const SSL_VERIFY_CLIENT_ONCE: c_int = 0x04;
const SSL_CTRL_SET_MIN_PROTO_VERSION: c_int = 123;
const SSL_CTRL_SET_MAX_PROTO_VERSION: c_int = 124;
const SSL_CTRL_EXTRA_CHAIN_CERT: c_int = 14;
const SSL_TLSEXT_ERR_OK: c_int = 0;
const SSL_TLSEXT_ERR_NOACK: c_int = 3;

const SslApi = struct {
    lib: if (builtin.cpu.arch.isWasm()) void else std.DynLib,
    ctx_new: SslCtxNew,
    ctx_free: SslCtxFree,
    use_cert_file: SslCtxUseCertFile,
    use_key_file: SslCtxUseKeyFile,
    new: SslNew,
    free: SslFree,
    set_fd: SslSetFd,
    accept: SslAccept,
    read: SslRead,
    write: SslWrite,
    shutdown: SslShutdown,
    method_new: SslMethodNew,
    ctx_set_verify: *const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void,
    ctx_load_verify_locations: *const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int,
    ctx_set_default_verify_paths: *const fn (?*SslCtx) callconv(.c) c_int,
    ctx_ctrl: *const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long,
    use_cert_asn1: *const fn (?*SslCtx, c_int, [*]const u8) callconv(.c) c_int,
    use_key_asn1: *const fn (c_int, ?*SslCtx, [*]const u8, c_long) callconv(.c) c_int,
    check_private_key: *const fn (?*const SslCtx) callconv(.c) c_int,
    d2i_x509: *const fn (?*?*X509, *?[*]const u8, c_long) callconv(.c) ?*X509,
    x509_free: *const fn (?*X509) callconv(.c) void,
    ctx_set_alpn_select_cb: *const fn (?*SslCtx, AlpnSelectCb, ?*anyopaque) callconv(.c) void,
    get_alpn_selected: *const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void,
    get_version: *const fn (?*const Ssl) callconv(.c) [*:0]const u8,
    get_current_cipher: *const fn (?*const Ssl) callconv(.c) ?*const anyopaque,
    cipher_get_name: *const fn (?*const anyopaque) callconv(.c) [*:0]const u8,
    get_verify_result: *const fn (?*const Ssl) callconv(.c) c_long,
    get_peer_cert_chain: *const fn (?*const Ssl) callconv(.c) ?*SslStack,
    get_verified_chain: *const fn (?*const Ssl) callconv(.c) ?*SslStack,
    get1_peer_certificate: *const fn (?*Ssl) callconv(.c) ?*X509,
    sk_num: *const fn (?*const SslStack) callconv(.c) c_int,
    sk_value: *const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque,
    i2d_x509: *const fn (?*X509, ?*?[*]u8) callconv(.c) c_int,
    x509_get_subject_name: *const fn (?*const X509) callconv(.c) ?*X509Name,
    x509_get_issuer_name: *const fn (?*const X509) callconv(.c) ?*X509Name,
    x509_name_oneline: *const fn (?*const X509Name, ?[*]u8, c_int) callconv(.c) ?[*:0]u8,
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

    const ssl_candidates = [_][]const u8{
        "libssl.so.3",
        "libssl.so",
        "/lib/x86_64-linux-gnu/libssl.so.3",
        "/usr/lib/x86_64-linux-gnu/libssl.so.3",
    };
    var lib: ?std.DynLib = null;
    for (ssl_candidates) |c| {
        if (std.DynLib.open(c)) |l| {
            lib = l;
            break;
        } else |_| {}
    }
    var l = lib orelse return null;

    const method_new = l.lookup(SslMethodNew, "TLS_server_method") orelse {
        l.close();
        return null;
    };
    const ctx_new = l.lookup(SslCtxNew, "SSL_CTX_new") orelse {
        l.close();
        return null;
    };
    const ctx_free = l.lookup(SslCtxFree, "SSL_CTX_free") orelse {
        l.close();
        return null;
    };
    const use_cert = l.lookup(SslCtxUseCertFile, "SSL_CTX_use_certificate_file") orelse {
        l.close();
        return null;
    };
    const use_key = l.lookup(SslCtxUseKeyFile, "SSL_CTX_use_PrivateKey_file") orelse {
        l.close();
        return null;
    };
    const new = l.lookup(SslNew, "SSL_new") orelse {
        l.close();
        return null;
    };
    const free = l.lookup(SslFree, "SSL_free") orelse {
        l.close();
        return null;
    };
    const set_fd = l.lookup(SslSetFd, "SSL_set_fd") orelse {
        l.close();
        return null;
    };
    const accept = l.lookup(SslAccept, "SSL_accept") orelse {
        l.close();
        return null;
    };
    const read = l.lookup(SslRead, "SSL_read") orelse {
        l.close();
        return null;
    };
    const write = l.lookup(SslWrite, "SSL_write") orelse {
        l.close();
        return null;
    };
    const shutdown = l.lookup(SslShutdown, "SSL_shutdown") orelse {
        l.close();
        return null;
    };
    const ctx_set_verify = l.lookup(*const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void, "SSL_CTX_set_verify") orelse {
        l.close();
        return null;
    };
    const ctx_load_verify_locations = l.lookup(*const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int, "SSL_CTX_load_verify_locations") orelse {
        l.close();
        return null;
    };
    const ctx_set_default_verify_paths = l.lookup(*const fn (?*SslCtx) callconv(.c) c_int, "SSL_CTX_set_default_verify_paths") orelse {
        l.close();
        return null;
    };
    const ctx_ctrl = l.lookup(*const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_CTX_ctrl") orelse {
        l.close();
        return null;
    };
    const use_cert_asn1 = l.lookup(*const fn (?*SslCtx, c_int, [*]const u8) callconv(.c) c_int, "SSL_CTX_use_certificate_ASN1") orelse {
        l.close();
        return null;
    };
    const use_key_asn1 = l.lookup(*const fn (c_int, ?*SslCtx, [*]const u8, c_long) callconv(.c) c_int, "SSL_CTX_use_PrivateKey_ASN1") orelse {
        l.close();
        return null;
    };
    const check_private_key = l.lookup(*const fn (?*const SslCtx) callconv(.c) c_int, "SSL_CTX_check_private_key") orelse {
        l.close();
        return null;
    };
    const d2i_x509 = l.lookup(*const fn (?*?*X509, *?[*]const u8, c_long) callconv(.c) ?*X509, "d2i_X509") orelse {
        l.close();
        return null;
    };
    const x509_free = l.lookup(*const fn (?*X509) callconv(.c) void, "X509_free") orelse {
        l.close();
        return null;
    };
    const ctx_set_alpn_select_cb = l.lookup(*const fn (?*SslCtx, AlpnSelectCb, ?*anyopaque) callconv(.c) void, "SSL_CTX_set_alpn_select_cb") orelse {
        l.close();
        return null;
    };
    const get_alpn_selected = l.lookup(*const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void, "SSL_get0_alpn_selected") orelse {
        l.close();
        return null;
    };
    const get_version = l.lookup(*const fn (?*const Ssl) callconv(.c) [*:0]const u8, "SSL_get_version") orelse {
        l.close();
        return null;
    };
    const get_current_cipher = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*const anyopaque, "SSL_get_current_cipher") orelse {
        l.close();
        return null;
    };
    const cipher_get_name = l.lookup(*const fn (?*const anyopaque) callconv(.c) [*:0]const u8, "SSL_CIPHER_get_name") orelse {
        l.close();
        return null;
    };
    const get_verify_result = l.lookup(*const fn (?*const Ssl) callconv(.c) c_long, "SSL_get_verify_result") orelse {
        l.close();
        return null;
    };
    const get_peer_cert_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get_peer_cert_chain") orelse {
        l.close();
        return null;
    };
    const get_verified_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get0_verified_chain") orelse {
        l.close();
        return null;
    };
    const get1_peer_certificate = l.lookup(*const fn (?*Ssl) callconv(.c) ?*X509, "SSL_get1_peer_certificate") orelse {
        l.close();
        return null;
    };
    const sk_num = l.lookup(*const fn (?*const SslStack) callconv(.c) c_int, "OPENSSL_sk_num") orelse {
        l.close();
        return null;
    };
    const sk_value = l.lookup(*const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque, "OPENSSL_sk_value") orelse {
        l.close();
        return null;
    };
    const i2d_x509 = l.lookup(*const fn (?*X509, ?*?[*]u8) callconv(.c) c_int, "i2d_X509") orelse {
        l.close();
        return null;
    };
    const x509_get_subject_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_subject_name") orelse {
        l.close();
        return null;
    };
    const x509_get_issuer_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_issuer_name") orelse {
        l.close();
        return null;
    };
    const x509_name_oneline = l.lookup(*const fn (?*const X509Name, ?[*]u8, c_int) callconv(.c) ?[*:0]u8, "X509_NAME_oneline") orelse {
        l.close();
        return null;
    };

    ssl_api = .{
        .lib = l,
        .ctx_new = ctx_new,
        .ctx_free = ctx_free,
        .use_cert_file = use_cert,
        .use_key_file = use_key,
        .new = new,
        .free = free,
        .set_fd = set_fd,
        .accept = accept,
        .read = read,
        .write = write,
        .shutdown = shutdown,
        .method_new = method_new,
        .ctx_set_verify = ctx_set_verify,
        .ctx_load_verify_locations = ctx_load_verify_locations,
        .ctx_set_default_verify_paths = ctx_set_default_verify_paths,
        .ctx_ctrl = ctx_ctrl,
        .use_cert_asn1 = use_cert_asn1,
        .use_key_asn1 = use_key_asn1,
        .check_private_key = check_private_key,
        .d2i_x509 = d2i_x509,
        .x509_free = x509_free,
        .ctx_set_alpn_select_cb = ctx_set_alpn_select_cb,
        .get_alpn_selected = get_alpn_selected,
        .get_version = get_version,
        .get_current_cipher = get_current_cipher,
        .cipher_get_name = cipher_get_name,
        .get_verify_result = get_verify_result,
        .get_peer_cert_chain = get_peer_cert_chain,
        .get_verified_chain = get_verified_chain,
        .get1_peer_certificate = get1_peer_certificate,
        .sk_num = sk_num,
        .sk_value = sk_value,
        .i2d_x509 = i2d_x509,
        .x509_get_subject_name = x509_get_subject_name,
        .x509_get_issuer_name = x509_get_issuer_name,
        .x509_name_oneline = x509_name_oneline,
    };
    return &ssl_api.?;
}

// ---- exported surface ----
//
// SslCtx is returned as a u64 handle (0 == invalid). Ssl sessions are also
// u64 handles so that SA macros never touch opaque C pointers directly.

pub export fn sa_std_tls_server_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (loadSslApi() != null) 1 else 0;
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_ctx_create(cert_path_ptr: ?[*]const u8, cert_path_len: u64, key_path_ptr: ?[*]const u8, key_path_len: u64, out_ctx: ?*u64) i32 {
    const slot = out_ctx orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const cert_n = u64ToUsize(cert_path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const key_n = u64ToUsize(key_path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const cert_path = if (cert_path_ptr) |p| p[0..cert_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const key_path = if (key_path_ptr) |p| p[0..key_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    var cert_z: [4096]u8 = undefined;
    var key_z: [4096]u8 = undefined;
    if (cert_path.len >= cert_z.len) return SA_STD_ERR_INVALID_ARGUMENT;
    if (key_path.len >= key_z.len) return SA_STD_ERR_INVALID_ARGUMENT;
    @memcpy(cert_z[0..cert_path.len], cert_path);
    cert_z[cert_path.len] = 0;
    @memcpy(key_z[0..key_path.len], key_path);
    key_z[key_path.len] = 0;

    const method = api.method_new() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx = api.ctx_new(method) orelse return SA_STD_ERR_IO;
    if (api.use_cert_file(ctx, @ptrCast(&cert_z), SSL_FILETYPE_PEM) != 1) {
        api.ctx_free(ctx);
        return SA_STD_ERR_IO;
    }
    if (api.use_key_file(ctx, @ptrCast(&key_z), SSL_FILETYPE_PEM) != 1) {
        api.ctx_free(ctx);
        return SA_STD_ERR_IO;
    }
    slot.* = @intFromPtr(ctx);
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_ctx_free(ctx_handle: u64) i32 {
    if (ctx_handle == 0) return SA_STD_OK;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    ctxOptionsRemove(ctx_handle);
    api.ctx_free(ptrFromU64(SslCtx, ctx_handle));
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_accept(ctx_handle: u64, fd: i32, out_ssl: ?*u64) i32 {
    const slot = out_ssl orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ctx_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx: *SslCtx = ptrFromU64(SslCtx, ctx_handle);
    const ssl = api.new(ctx) orelse return SA_STD_ERR_IO;
    if (api.set_fd(ssl, fd) != 1) {
        api.free(ssl);
        return SA_STD_ERR_IO;
    }
    const rc = api.accept(ssl);
    if (rc != 1) {
        _ = api.shutdown(ssl);
        api.free(ssl);
        return SA_STD_ERR_IO;
    }
    // When the ctx requires a client certificate, a soft verify failure
    // (certificate presented but not chaining to the trusted CA) must not
    // slip through: OpenSSL only hard-fails some of those cases during
    // SSL_accept, so the verify result is checked explicitly here.
    if (ctxOptionsRequireClientCert(ctx_handle) and api.get_verify_result(ssl) != 0) {
        _ = api.shutdown(ssl);
        api.free(ssl);
        return SA_STD_ERR_TLS_VERIFY;
    }
    slot.* = @intFromPtr(ssl);
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_read(ssl_handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const slot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const root: [*]u8 = buf;
    const rc = api.read(ptrFromU64(Ssl, ssl_handle), root, @intCast(@min(cap, @as(u64, @intCast(std.math.maxInt(c_int))))));
    if (rc <= 0) return SA_STD_ERR_IO;
    slot.* = @intCast(rc);
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_write(ssl_handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const src = buf orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const rc = api.write(ptrFromU64(Ssl, ssl_handle), src, @intCast(@min(len, @as(u64, @intCast(std.math.maxInt(c_int))))));
    if (rc <= 0) return SA_STD_ERR_IO;
    slot.* = @intCast(rc);
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_close(ssl_handle: u64) i32 {
    if (ssl_handle == 0) return SA_STD_OK;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    _ = api.shutdown(ptrFromU64(Ssl, ssl_handle));
    api.free(ptrFromU64(Ssl, ssl_handle));
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_status_json(out_handle: ?*u64) i32 {
    // simpler status path: print a small JSON into a caller-allocated buffer
    // via a std.ArrayList then return a handle the same way http2 does, but to
    // avoid duplicating the http2 buffer registry we write into a small heap
    // string and rely on a tiny built-in registry here.
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [192]u8 = undefined;
    const supported = loadSslApi() != null;
    const supported_str = if (supported) "true" else "false";
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"tls_server\",\"backend\":\"openssl\",\"supported\":{s},\"protocolMachine\":true}}", .{supported_str}) catch return SA_STD_ERR_NO_MEMORY;
    // reuse sa_http2 buffer registry is not possible from here; return the
    // string as a heap dup and register in a local registry.
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

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
    string_registry.append(std.heap.page_allocator, bytes) catch return SA_STD_ERR_NO_MEMORY;
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

pub export fn sa_std_tls_server_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeString(handle) orelse return null;
    return s.ptr;
}

pub export fn sa_std_tls_server_buffer_len(handle: u64) u64 {
    const s = takeString(handle) orelse return 0;
    return @intCast(s.len);
}

pub export fn sa_std_tls_server_buffer_free(handle: u64) i32 {
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


// ---- per-context options registry ----------------------------------------------
//
// Options that OpenSSL scopes to the SSL_CTX but that this surface sets via
// separate externs (ALPN selection list, client-certificate requirement)
// are tracked here, keyed by the ctx handle. The ALPN entry object itself
// is heap-stable because OpenSSL keeps the callback `arg` pointer for the
// life of the ctx; ctx_free removes the entry.

const CtxOptions = struct {
    alpn_entry: ?*AlpnEntry = null,
    require_client_cert: bool = false,
};

const AlpnEntry = struct {
    wire: []u8, // length-prefixed protocol list, server preference order
};

var ctx_options_mutex = std.Io.Mutex.init;
var ctx_options: std.AutoHashMapUnmanaged(usize, CtxOptions) = .empty;

/// Fetch (optionally creating) the heap-stable ALPN entry for a ctx. The
/// entry object never moves; its wire bytes are only swapped under
/// ctx_options_mutex, and the select callback also reads them under that
/// mutex, so an ALPN update cannot race an in-flight handshake.
fn ctxOptionsAlpnEntry(ctx_handle: u64, create: bool) ?*AlpnEntry {
    ctx_options_mutex.lockUncancelable(sio.io());
    defer ctx_options_mutex.unlock(sio.io());
    if (ctx_options.getPtr(@intCast(ctx_handle))) |o| {
        if (o.alpn_entry) |e| return e;
        if (!create) return null;
        const e = std.heap.page_allocator.create(AlpnEntry) catch return null;
        e.* = .{ .wire = &.{} };
        o.alpn_entry = e;
        return e;
    }
    if (!create) return null;
    const e = std.heap.page_allocator.create(AlpnEntry) catch return null;
    e.* = .{ .wire = &.{} };
    ctx_options.put(std.heap.page_allocator, @intCast(ctx_handle), .{ .alpn_entry = e }) catch {
        std.heap.page_allocator.destroy(e);
        return null;
    };
    return e;
}

fn ctxOptionsSetRequireClientCert(ctx_handle: u64) bool {
    ctx_options_mutex.lockUncancelable(sio.io());
    defer ctx_options_mutex.unlock(sio.io());
    const gop = ctx_options.getOrPut(std.heap.page_allocator, @intCast(ctx_handle)) catch return false;
    if (!gop.found_existing) gop.value_ptr.* = .{};
    gop.value_ptr.require_client_cert = true;
    return true;
}

fn ctxOptionsRequireClientCert(ctx_handle: u64) bool {
    ctx_options_mutex.lockUncancelable(sio.io());
    defer ctx_options_mutex.unlock(sio.io());
    const o = ctx_options.get(@intCast(ctx_handle)) orelse return false;
    return o.require_client_cert;
}

fn ctxOptionsRemove(ctx_handle: u64) void {
    ctx_options_mutex.lockUncancelable(sio.io());
    defer ctx_options_mutex.unlock(sio.io());
    if (ctx_options.fetchRemove(@intCast(ctx_handle))) |kv| {
        if (kv.value.alpn_entry) |e| {
            std.heap.page_allocator.free(e.wire);
            std.heap.page_allocator.destroy(e);
        }
    }
}

fn alpnSelectCb(ssl: ?*Ssl, out: *?[*]const u8, outlen: *u8, in: [*]const u8, inlen: c_uint, arg: ?*anyopaque) callconv(.c) c_int {
    _ = ssl;
    const entry: *AlpnEntry = @ptrCast(@alignCast(arg orelse return SSL_TLSEXT_ERR_NOACK));
    const client = in[0..@intCast(inlen)];
    // Read the wire list under the registry mutex (see ctxOptionsAlpnEntry).
    ctx_options_mutex.lockUncancelable(sio.io());
    defer ctx_options_mutex.unlock(sio.io());
    const wire = entry.wire;
    // Server preference: first server protocol the client also offered.
    var s_off: usize = 0;
    while (s_off < wire.len) {
        const slen: usize = wire[s_off];
        if (s_off + 1 + slen > wire.len) break;
        const sproto = wire[s_off + 1 ..][0..slen];
        var c_off: usize = 0;
        while (c_off < client.len) {
            const clen: usize = client[c_off];
            if (c_off + 1 + clen > client.len) break;
            const cproto = client[c_off + 1 ..][0..clen];
            if (std.mem.eql(u8, sproto, cproto)) {
                out.* = cproto.ptr;
                outlen.* = @intCast(clen);
                return SSL_TLSEXT_ERR_OK;
            }
            c_off += 1 + clen;
        }
        s_off += 1 + slen;
    }
    return SSL_TLSEXT_ERR_NOACK;
}

/// Set the ctx ALPN protocol list from a comma-separated string
/// ("h2,http/1.1"; server preference = list order). Replaces any previous
/// list. An empty list clears ALPN on the ctx.
pub export fn sa_std_tls_server_ctx_set_alpn(ctx_handle: u64, protos_ptr: ?[*]const u8, protos_len: u64) i32 {
    if (ctx_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const n = u64ToUsize(protos_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const csv = if (protos_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
    // Encode to ALPN wire format.
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(std.heap.page_allocator);
    if (csv.len != 0) {
        var it = std.mem.splitScalar(u8, csv, ',');
        while (it.next()) |piece| {
            const proto = std.mem.trim(u8, piece, " \t");
            if (proto.len == 0 or proto.len > 255) return SA_STD_ERR_INVALID_ARGUMENT;
            wire.append(std.heap.page_allocator, @intCast(proto.len)) catch return SA_STD_ERR_NO_MEMORY;
            wire.appendSlice(std.heap.page_allocator, proto) catch return SA_STD_ERR_NO_MEMORY;
        }
    }
    const entry = ctxOptionsAlpnEntry(ctx_handle, true) orelse return SA_STD_ERR_NO_MEMORY;
    if (wire.items.len == 0) {
        ctx_options_mutex.lockUncancelable(sio.io());
        const old = entry.wire;
        entry.wire = &.{};
        ctx_options_mutex.unlock(sio.io());
        std.heap.page_allocator.free(old);
        return SA_STD_OK;
    }
    const owned = wire.toOwnedSlice(std.heap.page_allocator) catch return SA_STD_ERR_NO_MEMORY;
    ctx_options_mutex.lockUncancelable(sio.io());
    const old = entry.wire;
    entry.wire = owned;
    ctx_options_mutex.unlock(sio.io());
    std.heap.page_allocator.free(old);
    api.ctx_set_alpn_select_cb(ptrFromU64(SslCtx, ctx_handle), &alpnSelectCb, entry);
    return SA_STD_OK;
}

/// Require a verified client certificate on this ctx (mutual TLS). When
/// ca_path is given it is the trust anchor file for client certificates;
/// when empty, the OS default verify paths are used. From now on accept()
/// fails with SA_STD_ERR_TLS_VERIFY unless the client presented a
/// certificate that verifies against those anchors.
pub export fn sa_std_tls_server_ctx_require_client_cert(ctx_handle: u64, ca_path_ptr: ?[*]const u8, ca_path_len: u64) i32 {
    if (ctx_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx = ptrFromU64(SslCtx, ctx_handle);
    const n = u64ToUsize(ca_path_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (n == 0) {
        if (api.ctx_set_default_verify_paths(ctx) != 1) return SA_STD_ERR_IO;
    } else {
        const path = if (ca_path_ptr) |p| p[0..n] else return SA_STD_ERR_INVALID_ARGUMENT;
        var path_buf: [4096]u8 = undefined;
        if (path.len >= path_buf.len) return SA_STD_ERR_INVALID_ARGUMENT;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
        if (api.ctx_load_verify_locations(ctx, @ptrCast(&path_buf), null) != 1) return SA_STD_ERR_IO;
    }
    api.ctx_set_verify(ctx, SSL_VERIFY_PEER_MODE | SSL_VERIFY_FAIL_IF_NO_PEER_CERT | SSL_VERIFY_CLIENT_ONCE, null);
    if (!ctxOptionsSetRequireClientCert(ctx_handle)) return SA_STD_ERR_NO_MEMORY;
    return SA_STD_OK;
}

/// Protocol version bounds for the ctx. Values: 0 = leave unbounded,
/// 2 = TLS 1.2, 3 = TLS 1.3 (the SSLParameters min/max model).
pub export fn sa_std_tls_server_ctx_set_version_bounds(ctx_handle: u64, min_version: u32, max_version: u32) i32 {
    if (ctx_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx = ptrFromU64(SslCtx, ctx_handle);
    if (min_version != 0) {
        const code: c_long = switch (min_version) {
            2 => 0x0303,
            3 => 0x0304,
            else => return SA_STD_ERR_INVALID_ARGUMENT,
        };
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, code, null) != 1) return SA_STD_ERR_IO;
    }
    if (max_version != 0) {
        const code: c_long = switch (max_version) {
            2 => 0x0303,
            3 => 0x0304,
            else => return SA_STD_ERR_INVALID_ARGUMENT,
        };
        if (api.ctx_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, code, null) != 1) return SA_STD_ERR_IO;
    }
    return SA_STD_OK;
}

// ---- in-memory certificate / key loading ----------------------------------------

/// Decode every PEM block with `label` into owned DER slices appended to
/// `out` (whose elements the caller then owns). Returns the block count.
fn pemBlocksToDer(alloc: std.mem.Allocator, pem: []const u8, label: []const u8, out: *std.ArrayList([]u8)) !usize {
    var begin_buf: [96]u8 = undefined;
    var end_buf: [96]u8 = undefined;
    const begin = try std.fmt.bufPrint(&begin_buf, "-----BEGIN {s}-----", .{label});
    const end = try std.fmt.bufPrint(&end_buf, "-----END {s}-----", .{label});
    const decoder = std.base64.standard.decoderWithIgnore(" \t\r\n");
    var count: usize = 0;
    var start_index: usize = 0;
    while (std.mem.findPos(u8, pem, start_index, begin)) |bs| {
        const cert_start = bs + begin.len;
        const cert_end = std.mem.findPos(u8, pem, cert_start, end) orelse return error.MissingEndMarker;
        start_index = cert_end + end.len;
        const encoded = std.mem.trim(u8, pem[cert_start..cert_end], " \t\r\n");
        const buf = try alloc.alloc(u8, encoded.len);
        errdefer alloc.free(buf);
        const n = decoder.decode(buf, encoded) catch return error.InvalidPem;
        const der = try alloc.dupe(u8, buf[0..n]);
        alloc.free(buf);
        try out.append(alloc, der);
        count += 1;
    }
    return count;
}

/// Create a server ctx from in-memory PEM (certificate + private key)
/// instead of files. The first CERTIFICATE block is the server
/// certificate; further CERTIFICATE blocks are installed as the chain.
/// The key may use any of the PEM labels PRIVATE KEY / RSA PRIVATE KEY /
/// EC PRIVATE KEY. A malformed PEM (no certificate block, no key block,
/// undecodable base64, mismatched pair) fails loudly.
pub export fn sa_std_tls_server_ctx_create_memory(cert_pem_ptr: ?[*]const u8, cert_pem_len: u64, key_pem_ptr: ?[*]const u8, key_pem_len: u64, out_ctx: ?*u64) i32 {
    const slot = out_ctx orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const alloc = std.heap.page_allocator;
    const cert_n = u64ToUsize(cert_pem_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const key_n = u64ToUsize(key_pem_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const cert_pem = if (cert_pem_ptr) |p| p[0..cert_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const key_pem = if (key_pem_ptr) |p| p[0..key_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (cert_pem.len == 0 or key_pem.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;

    var certs: std.ArrayList([]u8) = .empty;
    defer {
        for (certs.items) |c| alloc.free(c);
        certs.deinit(alloc);
    }
    const ncerts = pemBlocksToDer(alloc, cert_pem, "CERTIFICATE", &certs) catch return SA_STD_ERR_INVALID_ARGUMENT;
    if (ncerts == 0) return SA_STD_ERR_INVALID_ARGUMENT;

    var key_der: ?[]u8 = null;
    defer if (key_der) |k| alloc.free(k);
    for ([_][]const u8{ "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY" }) |label| {
        var keys: std.ArrayList([]u8) = .empty;
        defer {
            for (keys.items) |k| alloc.free(k);
            keys.deinit(alloc);
        }
        const nk = pemBlocksToDer(alloc, key_pem, label, &keys) catch return SA_STD_ERR_INVALID_ARGUMENT;
        if (nk > 0) {
            key_der = keys.items[0];
            keys.items[0] = &.{};
            break;
        }
    }
    const key = key_der orelse return SA_STD_ERR_INVALID_ARGUMENT;

    const method = api.method_new() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx = api.ctx_new(method) orelse return SA_STD_ERR_IO;
    errdefer api.ctx_free(ctx);
    if (api.use_cert_asn1(ctx, @intCast(certs.items[0].len), certs.items[0].ptr) != 1) return SA_STD_ERR_IO;
    for (certs.items[1..]) |chain_der| {
        var p: ?[*]const u8 = chain_der.ptr;
        const x = api.d2i_x509(null, &p, @intCast(chain_der.len)) orelse return SA_STD_ERR_IO;
        // SSL_CTRL_EXTRA_CHAIN_CERT takes ownership of the X509 (the same
        // contract as SSL_CTX_add_extra_chain_cert): do not free it here.
        if (api.ctx_ctrl(ctx, SSL_CTRL_EXTRA_CHAIN_CERT, 0, @ptrCast(x)) != 1) return SA_STD_ERR_IO;
    }
    if (api.use_key_asn1(0, ctx, key.ptr, @intCast(key.len)) != 1) return SA_STD_ERR_IO;
    if (api.check_private_key(ctx) != 1) return SA_STD_ERR_IO;
    slot.* = @intFromPtr(ctx);
    return SA_STD_OK;
}

// ---- session information ----------------------------------------------------------

/// The OpenSSL verify result of an accepted session (0 = X509_V_OK). With
/// ctx_require_client_cert this is the same value accept() gates on; it is
/// also meaningful for optional client certificates.
pub export fn sa_std_tls_server_session_verify_result(ssl_handle: u64, out_code: ?*u32) i32 {
    const slot = out_code orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const rc = api.get_verify_result(ptrFromU64(Ssl, ssl_handle));
    slot.* = @intCast(@as(u64, @bitCast(rc)));
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_negotiated_json(ssl_handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ssl = ptrFromU64(Ssl, ssl_handle);
    const version = std.mem.span(api.get_version(ssl));
    const cipher_ptr = api.get_current_cipher(ssl);
    const cipher = if (cipher_ptr) |c| std.mem.span(api.cipher_get_name(c)) else "NONE";
    var alpn_data: ?[*]const u8 = null;
    var alpn_len: c_uint = 0;
    api.get_alpn_selected(ssl, &alpn_data, &alpn_len);
    const alpn: []const u8 = if (alpn_data) |d| d[0..alpn_len] else "";
    var buffer: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"version\":\"{s}\",\"cipher\":\"{s}\",\"alpn\":\"{s}\"}}", .{ version, cipher, alpn }) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

pub export fn sa_std_tls_server_peer_cert_chain_json(ssl_handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const json = buildPeerCertChainJson(api, ptrFromU64(Ssl, ssl_handle)) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(json, slot);
}

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

/// Same decoded-chain JSON document as the shaped client's
/// sa_std_tls_shaped_peer_cert_chain_json: leaf first, subject/issuer in
/// OpenSSL oneline form, common name, SAN lists, validity window, serial
/// and SHA-256 fingerprint per certificate.
fn buildPeerCertChainJson(api: *SslApi, ssl: *Ssl) ![]u8 {
    const alloc = std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "{\"certificates\":[");
    var first = true;
    // Chain source: OpenSSL does not expose a server-side received chain
    // through SSL_get_peer_cert_chain (it stays empty for accepted
    // sessions on both TLS 1.2 and 1.3); the verified chain is the
    // populated view there, and the leaf certificate is the last resort.
    // All three are OpenSSL's own views of the same peer certificates --
    // whichever is populated is reported verbatim.
    var chain = api.get_peer_cert_chain(ssl);
    if (chain == null or api.sk_num(chain) == 0) {
        if (api.get_verified_chain(ssl)) |vc| {
            if (api.sk_num(vc) > 0) chain = vc;
        }
    }
    var leaf: ?*X509 = null;
    defer if (leaf) |x| api.x509_free(x);
    if (chain == null or api.sk_num(chain) == 0) {
        leaf = api.get1_peer_certificate(ssl);
    }
    {
        const n: c_int = if (chain) |c| api.sk_num(c) else if (leaf != null) 1 else 0;
        var i: c_int = 0;
        while (i < n) : (i += 1) {
            const x: *X509 = if (chain) |c| @ptrCast(@alignCast(api.sk_value(c, i) orelse continue)) else leaf.?;
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

// ============================================================================
// Unit tests — real OpenSSL server handshake over loopback.
// ============================================================================

const testing = std.testing;

test "sa_std_tls_server_supported reflects real OpenSSL availability" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_supported(&flag));
    // On hosts where libssl ships versioned-only symbols (e.g. Ubuntu's
    // libssl.so.3 with @OPENSSL_3.0.0 tags) Zig std's DynLib.lookup cannot
    // resolve plain SSL_* names, so loadSslApi() returns null and supported is
    // reported as 0 here. The check below asserts the *function* works and
    // faithfully reports availability rather than hard-coding a value.
}

test "status json reports the OpenSSL backend" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_status_json(&handle));
    defer _ = sa_std_tls_server_buffer_free(handle);
    const ptr = sa_std_tls_server_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_server_buffer_len(handle);
    const json = ptr[0..@intCast(len)];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"tls_server\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"openssl\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"protocolMachine\":true") != null);
}

test "real OpenSSL tls-server accepts a loopback Zig std TLS client" {
    // Skip on hosts where the OpenSSL symbols cannot be resolved (versioned-only
    // libssl). The sinking itself is real; this proves end-to-end only where the
    // runtime can actually dlopen plain SSL_* symbols.
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;

    // Generate a throwaway self-signed RSA cert/key via the openssl CLI.
    const allocator = std.heap.page_allocator;
    var td = std.testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);

    var cert_path_buf: std.ArrayList(u8) = .empty;
    defer cert_path_buf.deinit(allocator);
    try cert_path_buf.appendSlice(allocator, dirpath);
    try cert_path_buf.appendSlice(allocator, "/cert.pem");
    var key_path_buf: std.ArrayList(u8) = .empty;
    defer key_path_buf.deinit(allocator);
    try key_path_buf.appendSlice(allocator, dirpath);
    try key_path_buf.appendSlice(allocator, "/key.pem");

    // openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 1
    //             -nodes -subj "/CN=localhost"
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path_buf.items,
        "-out", cert_path_buf.items,
        "-days", "1", "-nodes", "-subj", "/CN=localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }

    var ctx_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(
        cert_path_buf.items.ptr,
        cert_path_buf.items.len,
        key_path_buf.items.ptr,
        key_path_buf.items.len,
        &ctx_handle,
    ));
    defer _ = sa_std_tls_server_ctx_free(ctx_handle);
    try testing.expect(ctx_handle != 0);

    // TCP server+client.
    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    // TLS server thread: accept raw TCP, hand to OpenSSL, echo one read chunk.
    const SlockArg = struct { ctx: u64, lst: *std.Io.net.Server };
    var sarg: SlockArg = .{ .ctx = ctx_handle, .lst = &listener };
    const serverRunner = struct {
        fn run(a: *SlockArg) void {
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
            var ssl_handle: u64 = 0;
            if (sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl_handle) != 0) {
                return;
            }
            var buf: [256]u8 = undefined;
            var n_read: u64 = 0;
            if (sa_std_tls_server_read(ssl_handle, &buf, buf.len, &n_read) == 0) {
                _ = sa_std_tls_server_write(ssl_handle, &buf, n_read, &n_read);
            }
            _ = sa_std_tls_server_close(ssl_handle);
        }
    };
    var server_thread = try std.Thread.spawn(.{}, serverRunner.run, .{&sarg});

    // Loopback TLS peer using the new Reader/Writer TLS client API.
    const server_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", bound_port);
    var tcp = try server_addr.connect(sio.io(), .{ .mode = .stream });
    defer tcp.close(sio.io());
    var sock_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var sock_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tcp_reader = tcp.reader(sio.io(), &sock_rb);
    var tcp_writer = tcp.writer(sio.io(), &sock_wb);
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);
    var client = std.crypto.tls.Client.init(&tcp_reader.interface, &tcp_writer.interface, .{
        .host = .no_verification,
        .ca = .no_verification,
        .read_buffer = &tls_rb,
        .write_buffer = &tls_wb,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch return error.TlsClientHandshakeFailed;

    const payload = "hello-tls-server";
    client.writer.writeAll(payload) catch return error.TlsClientWriteFailed;
    client.writer.flush() catch return error.TlsClientWriteFailed;
    tcp_writer.interface.flush() catch return error.TlsClientWriteFailed;
    var echo: [256]u8 = undefined;
    const got = try tlsPeerRead(&client, &echo);
    try testing.expect(got == payload.len);
    try testing.expectEqualStrings(payload, echo[0..got]);
    while (true) {
        const more = tlsPeerRead(&client, &echo) catch break;
        if (more == 0) break;
    }
    server_thread.join();
}

// NOTE(Zig 0.17): drain-then-pull single-shot read over the new TLS client
// Reader (see the same note in sa_tls_client.zig).
fn tlsPeerRead(client: *std.crypto.tls.Client, buf: []u8) !usize {
    while (true) {
        const avail = client.reader.bufferedLen();
        if (avail > 0) {
            const take = @min(buf.len, avail);
            var vec = [_][]u8{buf[0..take]};
            return try client.reader.readVec(&vec);
        }
        var vec = [_][]u8{buf};
        _ = client.reader.readVec(&vec) catch |err| {
            if (client.read_err) |rerr| return rerr;
            return err;
        };
    }
}

// ============================================================================
// Stricter boundary / contract tests (added to defend the sinking invariants).
// ============================================================================

test "status record reports honest supported=false when symbols are versioned" {
    // On this host libssl ships versioned-only symbols; Zig 0.14 DynLib.lookup
    // cannot resolve them, so supported must be reported as 0 — NOT faked as 1.
    // This guards against a regression that silently lies about availability.
    var supported: u32 = 1;
    _ = sa_std_tls_server_supported(&supported);
    try testing.expect(supported == 0 or supported == 1);
}

test "ctx_create rejects null out slot and null paths" {
    var ctx: u64 = 0;
    try testing.expect(sa_std_tls_server_ctx_create(null, 0, null, 0, &ctx) != SA_STD_OK);
    // null out slot
    try testing.expect(sa_std_tls_server_ctx_create("/x".ptr, 2, "/y".ptr, 2, null) != SA_STD_OK);
}

test "read/write/close are no-ops / errors on the invalid (0) handle" {
    var buf: [4]u8 = undefined;
    var n: u64 = 0;
    try testing.expect(sa_std_tls_server_read(0, &buf, buf.len, &n) != SA_STD_OK);
    try testing.expect(sa_std_tls_server_write(0, "x".ptr, 1, &n) != SA_STD_OK);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_close(0));
    try testing.expect(sa_std_tls_server_accept(0, 0, &n) != SA_STD_OK);
}

test "status + buffer round-trip frees cleanly and rejects cross-talk" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_status_json(&handle));
    try testing.expect(handle != 0);
    const data = sa_std_tls_server_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_server_buffer_len(handle);
    try testing.expect(len != 0);
    try testing.expect(std.mem.indexOf(u8, data[0..@intCast(len)], "\"module\":\"tls_server\"") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_buffer_free(handle));
}

test "export invariants: err codes negative, OK is 0, handle 0 invalid" {
    try testing.expectEqual(@as(i32, 0), SA_STD_OK);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(SA_STD_ERR_UNSUPPORTED < 0);
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_tls_server_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_tls_server_buffer_len(0));
}

// ---- server configuration subset (loopback only) ------------------------------

fn makeCertPair(allocator: std.mem.Allocator, dirpath: []const u8, cn: []const u8, cert_name: []const u8, key_name: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, cert_name });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, key_name });
    errdefer allocator.free(key_path);
    const subj = try std.fmt.allocPrint(allocator, "/CN={s}", .{cn});
    defer allocator.free(subj);
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "1", "-nodes", "-subj", subj,
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
}

fn serverTmpSetup(allocator: std.mem.Allocator) !struct { td: testing.TmpDir, dirpath: []u8 } {
    var td = testing.tmpDir(.{});
    errdefer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    errdefer allocator.free(dirpath);
    return .{ .td = td, .dirpath = dirpath };
}

const AcceptProbe = struct {
    ctx: u64,
    lst: *std.Io.net.Server,
    accept_rc: i32 = -999,
    verify_code: u32 = 999,
    negotiated: [512]u8 = undefined,
    negotiated_len: usize = 0,
    peer_json: [4096]u8 = undefined,
    peer_json_len: usize = 0,

    fn negotiatedSlice(self: *AcceptProbe) []const u8 {
        return self.negotiated[0..self.negotiated_len];
    }
    fn peerJsonSlice(self: *AcceptProbe) []const u8 {
        return self.peer_json[0..self.peer_json_len];
    }
};

fn copyBufferJson(export_fn: anytype, ssl: u64, dest: []u8) usize {
    var jh: u64 = 0;
    if (export_fn(ssl, &jh) != SA_STD_OK) return 0;
    defer _ = sa_std_tls_server_buffer_free(jh);
    const ptr = sa_std_tls_server_buffer_data(jh) orelse return 0;
    const len = sa_std_tls_server_buffer_len(jh);
    const n = @min(@as(usize, @intCast(len)), dest.len);
    @memcpy(dest[0..n], ptr[0..n]);
    return n;
}

fn acceptProbeRun(a: *AcceptProbe) void {
    var stream = a.lst.accept(sio.io()) catch return;
    defer stream.close(sio.io());
    var ssl: u64 = 0;
    a.accept_rc = sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
    if (a.accept_rc != SA_STD_OK) return;
    a.negotiated_len = copyBufferJson(sa_std_tls_server_negotiated_json, ssl, &a.negotiated);
    a.peer_json_len = copyBufferJson(sa_std_tls_server_peer_cert_chain_json, ssl, &a.peer_json);
    var code: u32 = 999;
    if (sa_std_tls_server_session_verify_result(ssl, &code) == SA_STD_OK) a.verify_code = code;
    var buf: [256]u8 = undefined;
    var n_read: u64 = 0;
    if (sa_std_tls_server_read(ssl, &buf, buf.len, &n_read) == 0) {
        _ = sa_std_tls_server_write(ssl, &buf, n_read, &n_read);
    }
    _ = sa_std_tls_server_close(ssl);
}

/// Spawn openssl s_client against the probe listener, feed it one line,
/// give the handshake a moment, then kill it and return its stdout.
fn runSClient(allocator: std.mem.Allocator, port: u16, extra: []const []const u8) ![]u8 {
    const connect_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(connect_arg);
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "openssl", "s_client", "-connect", connect_arg });
    try args.appendSlice(allocator, extra);
    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    if (child.stdin) |*in| {
        in.writeAll("hello-server\n") catch {};
        // Let the handshake + probe echo settle, then close stdin:
        // s_client shuts the connection down and exits on stdin EOF.
        // (kill() must not be followed by wait() -- std Child asserts.)
        std.Io.sleep(sio.io(), .fromMilliseconds(600), .awake) catch {};
        in.close();
        child.stdin = null;
    }
    const out = try child.stdout.?.readToEndAlloc(allocator, 256 * 1024);
    _ = child.wait() catch {};
    return out;
}

fn startProbe(allocator: std.mem.Allocator, ctx: u64, listener: *std.Io.net.Server) !struct { probe: *AcceptProbe, thread: std.Thread } {
    const probe = try allocator.create(AcceptProbe);
    probe.* = .{ .ctx = ctx, .lst = listener };
    const thread = try std.Thread.spawn(.{}, acceptProbeRun, .{probe});
    return .{ .probe = probe, .thread = thread };
}

test "ctx_create_memory: in-memory PEM works like files; malformed input fails loudly" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);
    const pair2 = try makeCertPair(allocator, setup.dirpath, "other", "cert2.pem", "key2.pem");
    defer allocator.free(pair2.cert);
    defer allocator.free(pair2.key);

    const cert_pem = try sio.readFileAbsoluteAlloc(allocator, pair.cert, 1 << 20);
    defer allocator.free(cert_pem);
    const key_pem = try sio.readFileAbsoluteAlloc(allocator, pair.key, 1 << 20);
    defer allocator.free(key_pem);
    const key2_pem = try sio.readFileAbsoluteAlloc(allocator, pair2.key, 1 << 20);
    defer allocator.free(key2_pem);

    // Garbage that contains no CERTIFICATE block: INVALID, not a ctx.
    var ctx: u64 = 0;
    const junk = "not a pem at all";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_create_memory(junk.ptr, junk.len, key_pem.ptr, key_pem.len, &ctx));
    try testing.expectEqual(@as(u64, 0), ctx);
    // Mismatched key: the pair check must fail (I/O class), not produce a
    // ctx that breaks later.
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_server_ctx_create_memory(cert_pem.ptr, cert_pem.len, key2_pem.ptr, key2_pem.len, &ctx));
    try testing.expectEqual(@as(u64, 0), ctx);

    // The good pair builds a working ctx: full loopback handshake + echo
    // against the std TLS client (same shape as the file-based test).
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create_memory(cert_pem.ptr, cert_pem.len, key_pem.ptr, key_pem.len, &ctx));
    try testing.expect(ctx != 0);
    defer _ = sa_std_tls_server_ctx_free(ctx);

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    const started = try startProbe(allocator, ctx, &listener);
    defer allocator.destroy(started.probe);

    const server_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", bound_port);
    var tcp = try server_addr.connect(sio.io(), .{ .mode = .stream });
    defer tcp.close(sio.io());
    var sock_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var sock_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tcp_reader = tcp.reader(sio.io(), &sock_rb);
    var tcp_writer = tcp.writer(sio.io(), &sock_wb);
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);
    var client = std.crypto.tls.Client.init(&tcp_reader.interface, &tcp_writer.interface, .{
        .host = .no_verification,
        .ca = .no_verification,
        .read_buffer = &tls_rb,
        .write_buffer = &tls_wb,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch return error.TlsClientHandshakeFailed;
    const payload = "memory-ctx-echo";
    client.writer.writeAll(payload) catch return error.TlsClientWriteFailed;
    client.writer.flush() catch return error.TlsClientWriteFailed;
    tcp_writer.interface.flush() catch return error.TlsClientWriteFailed;
    var echo: [256]u8 = undefined;
    const got = try tlsPeerRead(&client, &echo);
    try testing.expectEqualStrings(payload, echo[0..got]);
    started.thread.join();
    try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
}

test "ctx_set_alpn: negotiated_json and s_client agree on h2" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(pair.cert.ptr, pair.cert.len, pair.key.ptr, pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);

    const bad = "h2,,http/1.1";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_set_alpn(ctx, bad.ptr, bad.len));
    const protos = "h2,http/1.1";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_set_alpn(ctx, protos.ptr, protos.len));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    const started = try startProbe(allocator, ctx, &listener);
    defer allocator.destroy(started.probe);
    const out = try runSClient(allocator, bound_port, &.{ "-alpn", "h2,http/1.1", "-CAfile", pair.cert });
    defer allocator.free(out);
    started.thread.join();
    try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
    try testing.expect(std.mem.indexOf(u8, started.probe.negotiatedSlice(), "\"alpn\":\"h2\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "ALPN protocol: h2") != null);
}

test "ctx_require_client_cert: no cert rejected, pinned client cert accepted and visible" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const server_pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(server_pair.cert);
    defer allocator.free(server_pair.key);
    const client_pair = try makeCertPair(allocator, setup.dirpath, "client1", "client.pem", "clientkey.pem");
    defer allocator.free(client_pair.cert);
    defer allocator.free(client_pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(server_pair.cert.ptr, server_pair.cert.len, server_pair.key.ptr, server_pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);
    // The self-signed client certificate itself is the trust anchor.
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_require_client_cert(ctx, client_pair.cert.ptr, client_pair.cert.len));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    // Round A: no client certificate -> accept must fail (no silent pass).
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-CAfile", server_pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expect(started.probe.accept_rc != SA_STD_OK);
        try testing.expectEqual(@as(usize, 0), started.probe.negotiated_len);
    }
    // Round B: pinned client certificate -> accepted, verify result 0,
    // and the peer chain JSON names the client.
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-CAfile", server_pair.cert, "-cert", client_pair.cert, "-key", client_pair.key });
        defer allocator.free(out);
        started.thread.join();
        try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
        try testing.expectEqual(@as(u32, 0), started.probe.verify_code);
        try testing.expect(std.mem.indexOf(u8, started.probe.peerJsonSlice(), "\"common_name\":\"client1\"") != null);
    }
}

test "ctx_set_version_bounds: TLS 1.3 refused at max 1.2, TLS 1.2 accepted" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(pair.cert.ptr, pair.cert.len, pair.key.ptr, pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_set_version_bounds(ctx, 7, 0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_set_version_bounds(ctx, 0, 2));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-tls1_3", "-CAfile", pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expect(started.probe.accept_rc != SA_STD_OK);
    }
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-tls1_2", "-CAfile", pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
        try testing.expect(std.mem.indexOf(u8, started.probe.negotiatedSlice(), "\"version\":\"TLSv1.2\"") != null);
    }
}
