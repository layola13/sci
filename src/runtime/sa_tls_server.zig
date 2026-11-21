// TLS-server runtime binding for the sci/sa_std platform layer.
test "sa_tls_server_tests" { std.testing.refAllDecls(@import("sa_tls_server_test.zig")); }
//
// Real TLS server handshake backed by OpenSSL (libssl/libcrypto), lazily
// loaded via dlopen. Zig 0.14's std.crypto only provides a TLS *client*, so a
// real server side requires OpenSSL. This sinking places the real binding in
// the sci runtime so all plugins can reuse it instead of each hiding its own.
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative = error.

const std = @import("std");
pub const builtin = @import("builtin");
pub const sio = @import("sio");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_NO_MEMORY: i32 = -12;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
pub const SA_STD_ERR_UNSUPPORTED: i32 = -1;
pub const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub fn ptrFromU64(T: type, h: u64) *T {
    return @ptrFromInt(@as(usize, @intCast(h)));
}

pub const SslCtx = opaque {};
pub const Ssl = opaque {};
const SslMethod = opaque {};
pub const Bio = opaque {};
pub const X509 = opaque {};
const X509Store = opaque {};
pub const X509Name = opaque {};
pub const SslStack = opaque {};

pub const AlpnSelectCb = *const fn (?*Ssl, *?[*]const u8, *u8, [*]const u8, c_uint, ?*anyopaque) callconv(.c) c_int;

pub const SslMethodNew = *const fn () callconv(.c) ?*const SslMethod;
pub const SslCtxNew = *const fn (?*const SslMethod) callconv(.c) ?*SslCtx;
pub const SslCtxFree = *const fn (?*SslCtx) callconv(.c) void;
pub const SslCtxUseCertFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
pub const SslCtxUseKeyFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
pub const SslNew = *const fn (?*SslCtx) callconv(.c) ?*Ssl;
pub const SslFree = *const fn (?*Ssl) callconv(.c) void;
pub const SslSetFd = *const fn (?*Ssl, c_int) callconv(.c) c_int;
pub const SslAccept = *const fn (?*Ssl) callconv(.c) c_int;
pub const SslRead = *const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int;
pub const SslWrite = *const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int;
pub const SslShutdown = *const fn (?*Ssl) callconv(.c) c_int;
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

pub const SslApi = struct {
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
    x509_name_print_ex: *const fn (?*Bio, ?*const X509Name, c_int, c_ulong) callconv(.c) c_int,
    bio_s_mem: *const fn () callconv(.c) ?*anyopaque,
    bio_new: *const fn (?*anyopaque) callconv(.c) ?*Bio,
    bio_read: *const fn (?*Bio, [*]u8, c_int) callconv(.c) c_int,
    bio_free: *const fn (?*Bio) callconv(.c) c_int,
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

pub const loadSslApiNative = @import("sa_tls_server_ssl.zig").loadSslApiNative;

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
pub const sa_std_tls_server_session_verify_result = @import("sa_tls_server_cert.zig").sa_std_tls_server_session_verify_result;

pub const sa_std_tls_server_negotiated_json = @import("sa_tls_server_cert.zig").sa_std_tls_server_negotiated_json;

pub const sa_std_tls_server_peer_cert_chain_json = @import("sa_tls_server_cert.zig").sa_std_tls_server_peer_cert_chain_json;

pub const appendJsonEscaped = @import("sa_tls_server_cert.zig").appendJsonEscaped;

pub const appendHexUpper = @import("sa_tls_server_cert.zig").appendHexUpper;

pub const serialHex = @import("sa_tls_server_cert.zig").serialHex;

pub const collectSans = @import("sa_tls_server_cert.zig").collectSans;

/// Pinned X509_NAME_print_ex flags for the display rendering of
/// certificate names in the peer chain JSON: identical constant and
/// rationale as X509_NAME_DISPLAY_FLAGS in sa_tls_shaped.zig (the
/// XN_FLAG_ONELINE preset, spelled out bit by bit so the format can
/// never drift with library defaults).
pub const X509_NAME_DISPLAY_FLAGS = @import("sa_tls_server_cert.zig").X509_NAME_DISPLAY_FLAGS;

pub const appendX509DisplayName = @import("sa_tls_server_cert.zig").appendX509DisplayName;

/// Same decoded-chain JSON document as the shaped client's
/// sa_std_tls_shaped_peer_cert_chain_json: leaf first, subject/issuer in
/// the pinned display form (see X509_NAME_DISPLAY_FLAGS above; the
/// OpenSSL 3 spaced rendering, never the deprecated oneline slash
/// form), common name, SAN lists, validity window, serial
/// and SHA-256 fingerprint per certificate.
pub const buildPeerCertChainJson = @import("sa_tls_server_cert.zig").buildPeerCertChainJson;

// ============================================================================
// Unit tests — real OpenSSL server handshake over loopback.
// ============================================================================

pub const testing = std.testing;




// NOTE(Zig 0.17): drain-then-pull single-shot read over the new TLS client
// Reader (see the same note in sa_tls_client.zig).

// ============================================================================
// Stricter boundary / contract tests (added to defend the sinking invariants).
// ============================================================================






// ---- server configuration subset (loopback only) ------------------------------






// Spawn openssl s_client against the probe listener, feed it one line,
// give the handshake a moment, then kill it and return its stdout.





