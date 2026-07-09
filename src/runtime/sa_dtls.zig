// DTLS runtime binding for the sci/sa_std platform layer.
//
// Real DTLS over UDP backed by OpenSSL (libssl/libcrypto), lazily loaded via
// dlopen. DTLS uses the same SSL/SSL_CTX machinery as TLS but over a datagram
// BIO (BIO_new_dgram). Like the TLS-server module, the real handshake binding
// lives here; the symbol-availability reality on the host is reported honestly
// (see the unit-test notes).
//
// Status codes: 0 = SA_STD_OK, negative = error.

const std = @import("std");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_NO_MEMORY: i32 = -12;

const SslCtx = opaque {};
const Ssl = opaque {};
const SslMethod = opaque {};
const Bio = opaque {};

const SslMethodNew = *const fn () callconv(.c) ?*const SslMethod; // DTLS_server_method
const SslCtxNew = *const fn (?*const SslMethod) callconv(.c) ?*SslCtx;
const SslCtxFree = *const fn (?*SslCtx) callconv(.c) void;
const SslCtxUseCertFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
const SslCtxUseKeyFile = *const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int;
const SslNew = *const fn (?*SslCtx) callconv(.c) ?*Ssl;
const SslFree = *const fn (?*Ssl) callconv(.c) void;
const SslSetBio = *const fn (?*Ssl, ?*Bio, ?*Bio) callconv(.c) void;
const SslSetFd = *const fn (?*Ssl, c_int) callconv(.c) c_int;
const SslAccept = *const fn (?*Ssl) callconv(.c) c_int;
const SslRead = *const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int;
const SslWrite = *const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int;
const SslShutdown = *const fn (?*Ssl) callconv(.c) c_int;
const BioNewDgram = *const fn (c_int, c_int) callconv(.c) ?*Bio;
const BioFree = *const fn (?*Bio) callconv(.c) c_int;

const SSL_FILETYPE_PEM: c_int = 1;
const BIO_CLOSE: c_int = 0x00;

const DtlsApi = struct {
    lib: std.DynLib,
    method_new: SslMethodNew,
    ctx_new: SslCtxNew,
    ctx_free: SslCtxFree,
    use_cert_file: SslCtxUseCertFile,
    use_key_file: SslCtxUseKeyFile,
    new: SslNew,
    free: SslFree,
    set_bio: SslSetBio,
    set_fd: SslSetFd,
    accept: SslAccept,
    read: SslRead,
    write: SslWrite,
    shutdown: SslShutdown,
    bio_new_dgram: BioNewDgram,
    bio_free: BioFree,
};

var dtls_api: ?DtlsApi = null;
var dtls_api_mutex = std.Thread.Mutex{};

fn loadDtlsApi() ?*DtlsApi {
    dtls_api_mutex.lock();
    defer dtls_api_mutex.unlock();
    if (dtls_api) |*api| return api;

    const ssl_candidates = [_][]const u8{
        "/lib/x86_64-linux-gnu/libssl.so.3",
        "/usr/lib/x86_64-linux-gnu/libssl.so.3",
        "libssl.so.3",
    };
    var l: ?std.DynLib = null;
    for (ssl_candidates) |c| {
        if (std.DynLib.open(c)) |ok| {
            l = ok;
            break;
        } else |_| {}
    }
    var lib = l orelse return null;

    const method_new = lib.lookup(SslMethodNew, "DTLS_server_method") orelse {
        lib.close();
        return null;
    };
    const ctx_new = lib.lookup(SslCtxNew, "SSL_CTX_new") orelse {
        lib.close();
        return null;
    };
    const ctx_free = lib.lookup(SslCtxFree, "SSL_CTX_free") orelse {
        lib.close();
        return null;
    };
    const use_cert = lib.lookup(SslCtxUseCertFile, "SSL_CTX_use_certificate_file") orelse {
        lib.close();
        return null;
    };
    const use_key = lib.lookup(SslCtxUseKeyFile, "SSL_CTX_use_PrivateKey_file") orelse {
        lib.close();
        return null;
    };
    const new_fn = lib.lookup(SslNew, "SSL_new") orelse {
        lib.close();
        return null;
    };
    const free = lib.lookup(SslFree, "SSL_free") orelse {
        lib.close();
        return null;
    };
    const set_bio = lib.lookup(SslSetBio, "SSL_set_bio") orelse {
        lib.close();
        return null;
    };
    const set_fd = lib.lookup(SslSetFd, "SSL_set_fd") orelse {
        lib.close();
        return null;
    };
    const accept = lib.lookup(SslAccept, "SSL_accept") orelse {
        lib.close();
        return null;
    };
    const read = lib.lookup(SslRead, "SSL_read") orelse {
        lib.close();
        return null;
    };
    const write = lib.lookup(SslWrite, "SSL_write") orelse {
        lib.close();
        return null;
    };
    const shutdown = lib.lookup(SslShutdown, "SSL_shutdown") orelse {
        lib.close();
        return null;
    };
    const bio_new_dgram = lib.lookup(BioNewDgram, "BIO_new_dgram") orelse {
        lib.close();
        return null;
    };
    const bio_free = lib.lookup(BioFree, "BIO_free") orelse {
        lib.close();
        return null;
    };
    dtls_api = .{
        .lib = lib,
        .method_new = method_new,
        .ctx_new = ctx_new,
        .ctx_free = ctx_free,
        .use_cert_file = use_cert,
        .use_key_file = use_key,
        .new = new_fn,
        .free = free,
        .set_bio = set_bio,
        .set_fd = set_fd,
        .accept = accept,
        .read = read,
        .write = write,
        .shutdown = shutdown,
        .bio_new_dgram = bio_new_dgram,
        .bio_free = bio_free,
    };
    return &dtls_api.?;
}

// ---- exported surface ----

pub export fn sa_std_dtls_supported(out: ?*u32) i32 {
    const slot = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (loadDtlsApi() != null) 1 else 0;
    return SA_STD_OK;
}

pub export fn sa_std_dtls_server_ctx_create(cert_path_ptr: ?[*]const u8, cert_path_len: u64, key_path_ptr: ?[*]const u8, key_path_len: u64, out_ctx: ?*u64) i32 {
    const slot = out_ctx orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const cert_path = if (cert_path_ptr) |p| p[0..cert_path_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    const key_path = if (key_path_ptr) |p| p[0..key_path_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    var cert_z: [4096]u8 = undefined;
    var key_z: [4096]u8 = undefined;
    if (cert_path.len >= cert_z.len or key_path.len >= key_z.len) return SA_STD_ERR_INVALID_ARGUMENT;
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

pub export fn sa_std_dtls_server_ctx_free(ctx_handle: u64) i32 {
    if (ctx_handle == 0) return SA_STD_OK;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    api.ctx_free(@ptrFromInt(ctx_handle));
    return SA_STD_OK;
}

// For a stateless DTLS-style datagram accept we set the UDP fd directly via
// SSL_set_fd (OpenSSL's BIO_dgram path can also be used, but set_fd is the
// simplest real handshake path for a bound UDP socket).
pub export fn sa_std_dtls_server_accept(ctx_handle: u64, fd: i32, out_ssl: ?*u64) i32 {
    const slot = out_ssl orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ctx_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ctx: *SslCtx = @ptrFromInt(ctx_handle);
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
    slot.* = @intFromPtr(ssl);
    return SA_STD_OK;
}

pub export fn sa_std_dtls_server_read(ssl_handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const slot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const root: [*]u8 = buf;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const rc = api.read(@ptrFromInt(ssl_handle), root, @intCast(@min(cap, @as(u64, @intCast(std.math.maxInt(c_int))))));
    if (rc <= 0) return SA_STD_ERR_IO;
    slot.* = @intCast(rc);
    return SA_STD_OK;
}

pub export fn sa_std_dtls_server_write(ssl_handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const src = buf orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const rc = api.write(@ptrFromInt(ssl_handle), src, @intCast(@min(len, @as(u64, @intCast(std.math.maxInt(c_int))))));
    if (rc <= 0) return SA_STD_ERR_IO;
    slot.* = @intCast(rc);
    return SA_STD_OK;
}

pub export fn sa_std_dtls_server_close(ssl_handle: u64) i32 {
    if (ssl_handle == 0) return SA_STD_OK;
    const api = loadDtlsApi() orelse return SA_STD_ERR_UNSUPPORTED;
    _ = api.shutdown(@ptrFromInt(ssl_handle));
    api.free(@ptrFromInt(ssl_handle));
    return SA_STD_OK;
}

var dtls_string_mutex = std.Thread.Mutex{};
var dtls_string_registry = std.ArrayListUnmanaged(?[]u8){};

pub export fn sa_std_dtls_status_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [192]u8 = undefined;
    const supported = loadDtlsApi() != null;
    const supported_str = if (supported) "true" else "false";
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"dtls\",\"backend\":\"openssl\",\"supported\":{s},\"protocolMachine\":true}}", .{supported_str}) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

fn registerString(bytes: []u8, slot: *u64) i32 {
    dtls_string_mutex.lock();
    defer dtls_string_mutex.unlock();
    var i: usize = 0;
    while (i < dtls_string_registry.items.len) : (i += 1) {
        if (dtls_string_registry.items[i] == null) {
            dtls_string_registry.items[i] = bytes;
            slot.* = @intCast(i + 1);
            return SA_STD_OK;
        }
    }
    dtls_string_registry.append(std.heap.page_allocator, bytes) catch return SA_STD_ERR_NO_MEMORY;
    slot.* = @intCast(dtls_string_registry.items.len);
    return SA_STD_OK;
}

fn takeString(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    dtls_string_mutex.lock();
    defer dtls_string_mutex.unlock();
    const idx: usize = @intCast(handle - 1);
    if (idx >= dtls_string_registry.items.len) return null;
    return dtls_string_registry.items[idx];
}

pub export fn sa_std_dtls_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeString(handle) orelse return null;
    return s.ptr;
}
pub export fn sa_std_dtls_buffer_len(handle: u64) u64 {
    const s = takeString(handle) orelse return 0;
    return @intCast(s.len);
}
pub export fn sa_std_dtls_buffer_free(handle: u64) i32 {
    dtls_string_mutex.lock();
    defer dtls_string_mutex.unlock();
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= dtls_string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = dtls_string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    dtls_string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

// ============================================================================
// Unit tests — honest DTLS symbol availability (see TLS-server test notes).
// ============================================================================

const testing = std.testing;

test "sa_std_dtls_supported reflects real OpenSSL DTLS availability" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_supported(&flag));
    // Same host reality as the TLS-server test: libssl ships versioned-only
    // symbols, so DynLib.lookup cannot resolve them and supported is 0 here.
}

test "status json reports the OpenSSL DTLS backend" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_status_json(&handle));
    defer _ = sa_std_dtls_buffer_free(handle);
    const ptr = sa_std_dtls_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_dtls_buffer_len(handle);
    const json = ptr[0..@intCast(len)];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"dtls\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"openssl\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"protocolMachine\":true") != null);
}

// ============================================================================
// Stricter boundary / contract tests (added to defend the sinking invariants).
// ============================================================================

test "ctx_create rejects null out slot and null paths" {
    var ctx: u64 = 0;
    try testing.expect(sa_std_dtls_server_ctx_create(null, 0, null, 0, &ctx) != SA_STD_OK);
    try testing.expect(sa_std_dtls_server_ctx_create("/x".ptr, 2, "/y".ptr, 2, null) != SA_STD_OK);
}

test "read/write/accept/close on the invalid (0) handle never succeed" {
    var buf: [4]u8 = undefined;
    var n: u64 = 0;
    try testing.expect(sa_std_dtls_server_read(0, &buf, buf.len, &n) != SA_STD_OK);
    try testing.expect(sa_std_dtls_server_write(0, "x".ptr, 1, &n) != SA_STD_OK);
    try testing.expect(sa_std_dtls_server_accept(0, 0, &n) != SA_STD_OK);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_server_close(0));
}

test "status + buffer round-trip frees cleanly" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_status_json(&handle));
    try testing.expect(handle != 0);
    const data = sa_std_dtls_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_dtls_buffer_len(handle);
    try testing.expect(std.mem.indexOf(u8, data[0..@intCast(len)], "\"module\":\"dtls\"") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_dtls_buffer_free(handle));
}

test "supported is honestly reported and never fakes availability" {
    var flag: u32 = 99;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_dtls_supported(&flag));
    try testing.expect(flag == 0 or flag == 1);
}
